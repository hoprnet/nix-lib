#include <openssl/crypto.h>

unsigned long probe_openssl_version(void) {
    return OpenSSL_version_num();
}
