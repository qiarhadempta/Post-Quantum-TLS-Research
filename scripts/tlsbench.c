#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <getopt.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/provider.h>

struct result {
    char status[16];
    double tcp_ms, tls_ms, total_ms;
    unsigned long err;
};

static double now_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1000.0 + t.tv_nsec / 1e6;
}

static int wait_fd(int fd, short events, double deadline) {
    double rem = deadline - now_ms();
    if (rem <= 0) return 0;
    struct pollfd p;
    p.fd = fd; p.events = events; p.revents = 0;
    int r = poll(&p, 1, (int)rem + 1);
    if (r < 0) return (errno == EINTR) ? 1 : -1;
    return r > 0 ? 1 : 0;
}

static int first_ok_reported = 0;

static void run_one(SSL_CTX *ctx, const struct sockaddr_in *addr, double deadline_ms, struct result *r) {
    int fd, rc, w, soerr = 0, e, ret;
    socklen_t sl = sizeof soerr;
    double t0, t1, t2, deadline;
    SSL *ssl;

    memset(r, 0, sizeof *r);
    r->tcp_ms = r->tls_ms = r->total_ms = -1;

    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) { strcpy(r->status, "socket_error"); r->err = errno; return; }
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);

    t0 = now_ms();
    deadline = t0 + deadline_ms;

    rc = connect(fd, (const struct sockaddr *)addr, sizeof *addr);
    if (rc < 0) {
        if (errno != EINPROGRESS) { strcpy(r->status, "tcp_error"); r->err = errno; goto out_fd; }
        w = wait_fd(fd, POLLOUT, deadline);
        if (w == 0) { strcpy(r->status, "timeout_tcp"); r->total_ms = now_ms() - t0; goto out_fd; }
        if (w < 0)  { strcpy(r->status, "tcp_error"); r->err = errno; goto out_fd; }
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &sl);
        if (soerr) { strcpy(r->status, "tcp_error"); r->err = (unsigned long)soerr; goto out_fd; }
    }
    t1 = now_ms();
    r->tcp_ms = t1 - t0;

    ssl = SSL_new(ctx);
    if (!ssl) { strcpy(r->status, "tls_error"); r->err = ERR_peek_last_error(); goto out_fd; }
    SSL_set_fd(ssl, fd);
    SSL_set_connect_state(ssl);

    for (;;) {
        ERR_clear_error();
        ret = SSL_do_handshake(ssl);
        if (ret == 1) { strcpy(r->status, "ok"); break; }
        e = SSL_get_error(ssl, ret);
        if (e == SSL_ERROR_WANT_READ || e == SSL_ERROR_WANT_WRITE) {
            w = wait_fd(fd, e == SSL_ERROR_WANT_READ ? POLLIN : POLLOUT, deadline);
            if (w == 0) { strcpy(r->status, "timeout_tls"); break; }
            if (w < 0)  { strcpy(r->status, "tls_error"); r->err = errno; break; }
            continue;
        }
        strcpy(r->status, "tls_error");
        r->err = ERR_peek_last_error();
        break;
    }
    t2 = now_ms();
    r->tls_ms = t2 - t1;
    r->total_ms = t2 - t0;

    if (!first_ok_reported && strcmp(r->status, "ok") == 0) {
        fprintf(stderr, "first ok handshake: negotiated_group=0x%x cipher=%s\n",
                (unsigned)SSL_get_negotiated_group(ssl), SSL_get_cipher_name(ssl));
        first_ok_reported = 1;
    }
    SSL_free(ssl);
out_fd:
    close(fd);
}

static void usage(const char *p) {
    fprintf(stderr,
        "usage: %s -g GROUP -s SIGALG -c CAFILE -o OUT.csv -l LABEL [options]\n"
        "  -a ADDR      server address (default 10.0.0.2)\n"
        "  -p PORT      server port (default 4433)\n"
        "  -n N         measured handshakes (default 100)\n"
        "  -w W         warm-up handshakes, written but flagged (default 5)\n"
        "  -d MS        deadline per handshake in ms (default 10000)\n"
        "  -r RTT       RTT label for the CSV (ms)\n"
        "  -L LOSS      loss label for the CSV (percent per direction)\n"
        "  -m DIR       oqsprovider module directory (default $OQS_MODULES)\n"
        "  -P           do not load oqsprovider (classical algorithms only)\n", p);
}

int main(int argc, char **argv) {
    const char *addr_s = "10.0.0.2", *group = NULL, *sigalg = NULL, *cafile = NULL;
    const char *out = NULL, *label = NULL, *mods = getenv("OQS_MODULES");
    int port = 4433, n = 100, warm = 5, no_oqs = 0, opt;
    double deadline = 10000, rtt = 0, loss = 0;

    while ((opt = getopt(argc, argv, "a:p:g:s:c:o:l:n:w:d:r:L:m:P")) != -1) {
        switch (opt) {
        case 'a': addr_s = optarg; break;
        case 'p': port = atoi(optarg); break;
        case 'g': group = optarg; break;
        case 's': sigalg = optarg; break;
        case 'c': cafile = optarg; break;
        case 'o': out = optarg; break;
        case 'l': label = optarg; break;
        case 'n': n = atoi(optarg); break;
        case 'w': warm = atoi(optarg); break;
        case 'd': deadline = atof(optarg); break;
        case 'r': rtt = atof(optarg); break;
        case 'L': loss = atof(optarg); break;
        case 'm': mods = optarg; break;
        case 'P': no_oqs = 1; break;
        default: usage(argv[0]); return 2;
        }
    }
    if (!group || !sigalg || !cafile || !out || !label) { usage(argv[0]); return 2; }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, addr_s, &addr.sin_addr) != 1) { fprintf(stderr, "bad address\n"); return 2; }

    if (mods) OSSL_PROVIDER_set_default_search_path(NULL, mods);
    if (!OSSL_PROVIDER_load(NULL, "default")) { ERR_print_errors_fp(stderr); return 1; }
    if (!no_oqs && !OSSL_PROVIDER_load(NULL, "oqsprovider")) {
        fprintf(stderr, "cannot load oqsprovider (modules dir: %s)\n", mods ? mods : "(none)");
        ERR_print_errors_fp(stderr);
        return 1;
    }

    SSL_CTX *ctx = SSL_CTX_new(TLS_client_method());
    if (!ctx) { ERR_print_errors_fp(stderr); return 1; }
    SSL_CTX_set_min_proto_version(ctx, TLS1_3_VERSION);
    SSL_CTX_set_max_proto_version(ctx, TLS1_3_VERSION);
    if (SSL_CTX_set1_groups_list(ctx, group) != 1) { fprintf(stderr, "bad group: %s\n", group); ERR_print_errors_fp(stderr); return 1; }
    if (SSL_CTX_set1_sigalgs_list(ctx, sigalg) != 1) { fprintf(stderr, "bad sigalg: %s\n", sigalg); ERR_print_errors_fp(stderr); return 1; }
    if (SSL_CTX_load_verify_locations(ctx, cafile, NULL) != 1) { fprintf(stderr, "cannot load CA file: %s\n", cafile); ERR_print_errors_fp(stderr); return 1; }
    SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL);
    SSL_CTX_set_session_cache_mode(ctx, SSL_SESS_CACHE_OFF);
    SSL_CTX_set_options(ctx, SSL_OP_NO_TICKET);

    struct stat st;
    int need_header = (stat(out, &st) != 0 || st.st_size == 0);
    FILE *f = fopen(out, "a");
    if (!f) { perror("open output"); return 1; }
    if (need_header)
        fprintf(f, "epoch_s,label,rtt_ms,loss_pct,deadline_ms,seq,warmup,status,tcp_ms,tls_ms,total_ms,err\n");

    int total = warm + n, ok = 0, bad = 0;
    for (int seq = 1; seq <= total; seq++) {
        struct result r;
        run_one(ctx, &addr, deadline, &r);
        fprintf(f, "%ld,%s,%g,%g,%g,%d,%d,%s,%.3f,%.3f,%.3f,%lu\n",
                (long)time(NULL), label, rtt, loss, deadline, seq, seq <= warm ? 1 : 0,
                r.status, r.tcp_ms, r.tls_ms, r.total_ms, r.err);
        fflush(f);
        if (seq % 50 == 0) fsync(fileno(f));
        if (seq > warm) { if (strcmp(r.status, "ok") == 0) ok++; else bad++; }
    }
    fsync(fileno(f));
    fclose(f);
    fprintf(stderr, "label=%s rtt=%g loss=%g: measured=%d ok=%d not_ok=%d (warm-up=%d) -> %s\n",
            label, rtt, loss, n, ok, bad, warm, out);
    SSL_CTX_free(ctx);
    return 0;
}
