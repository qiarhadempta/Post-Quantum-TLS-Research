#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <time.h>
#include <oqs/oqs.h>

static double now_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1000.0 + t.tv_nsec / 1e6;
}

/* lowercase + '-' -> '_' so name matching does not depend on spelling */
static void normalize(const char *in, char *out, size_t n) {
    size_t i = 0;
    for (; in[i] && i + 1 < n; i++)
        out[i] = (in[i] == '-') ? '_' : (char)tolower((unsigned char)in[i]);
    out[i] = '\0';
}

static int is_target_sig(const char *name) {
    char b[128];
    normalize(name, b, sizeof b);
    if (strstr(b, "ml_dsa_44") && !strstr(b, "prehash")) return 1;
    if (strstr(b, "slh") && strstr(b, "sha2_128f") && !strstr(b, "prehash")) return 1;
    return 0;
}

static void test_kem(const char *name) {
    OQS_KEM *kem = OQS_KEM_new(name);
    if (!kem) { printf("[KEM] %s: NOT AVAILABLE\n", name); return; }
    uint8_t *pk = malloc(kem->length_public_key);
    uint8_t *sk = malloc(kem->length_secret_key);
    uint8_t *ct = malloc(kem->length_ciphertext);
    uint8_t *s1 = malloc(kem->length_shared_secret);
    uint8_t *s2 = malloc(kem->length_shared_secret);
    int ok = OQS_KEM_keypair(kem, pk, sk) == OQS_SUCCESS
          && OQS_KEM_encaps(kem, ct, s1, pk) == OQS_SUCCESS
          && OQS_KEM_decaps(kem, s2, ct, sk) == OQS_SUCCESS
          && memcmp(s1, s2, kem->length_shared_secret) == 0;
    printf("[KEM] %-14s pk=%zu ct=%zu ss=%zu roundtrip=%s\n", name,
           kem->length_public_key, kem->length_ciphertext,
           kem->length_shared_secret, ok ? "OK" : "FAIL");
    free(pk); free(sk); free(ct); free(s1); free(s2);
    OQS_KEM_free(kem);
}

static void test_sig(const char *name) {
    OQS_SIG *sig = OQS_SIG_new(name);
    if (!sig) { printf("[SIG] %s: NOT AVAILABLE\n", name); return; }
    uint8_t *pk = malloc(sig->length_public_key);
    uint8_t *sk = malloc(sig->length_secret_key);
    uint8_t *sg = malloc(sig->length_signature);
    const uint8_t msg[] = "verification message";
    size_t siglen = 0;
    int ok = OQS_SIG_keypair(sig, pk, sk) == OQS_SUCCESS;
    double t0 = now_ms();
    ok = ok && OQS_SIG_sign(sig, sg, &siglen, msg, sizeof msg, sk) == OQS_SUCCESS;
    double t1 = now_ms();
    ok = ok && OQS_SIG_verify(sig, msg, sizeof msg, sg, siglen, pk) == OQS_SUCCESS;
    printf("[SIG] %-26s pk=%zu sig=%zu sign=%.2f ms verify=%s\n", name,
           sig->length_public_key, siglen, t1 - t0, ok ? "OK" : "FAIL");
    free(pk); free(sk); free(sg);
    OQS_SIG_free(sig);
}

int main(void) {
    printf("liboqs version: %s\n", OQS_version());
    test_kem("ML-KEM-512");
    int found = 0;
    for (size_t i = 0; i < OQS_SIG_alg_count(); i++) {
        const char *name = OQS_SIG_alg_identifier(i);
        if (OQS_SIG_alg_is_enabled(name) && is_target_sig(name)) {
            test_sig(name);
            found++;
        }
    }
    if (!found) printf("[SIG] no matching ML-DSA-44 / SLH-DSA-SHA2-128f variant found\n");
    return 0;
}
