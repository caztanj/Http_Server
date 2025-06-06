/* $OpenBSD: apps.h,v 1.42 2025/01/02 13:11:26 tb Exp $ */
/* Copyright (C) 1995-1998 Eric Young (eay@cryptsoft.com)
 * All rights reserved.
 *
 * This package is an SSL implementation written
 * by Eric Young (eay@cryptsoft.com).
 * The implementation was written so as to conform with Netscapes SSL.
 *
 * This library is free for commercial and non-commercial use as long as
 * the following conditions are aheared to.  The following conditions
 * apply to all code found in this distribution, be it the RC4, RSA,
 * lhash, DES, etc., code; not just the SSL code.  The SSL documentation
 * included with this distribution is covered by the same copyright terms
 * except that the holder is Tim Hudson (tjh@cryptsoft.com).
 *
 * Copyright remains Eric Young's, and as such any Copyright notices in
 * the code are not to be removed.
 * If this package is used in a product, Eric Young should be given attribution
 * as the author of the parts of the library used.
 * This can be in the form of a textual message at program startup or
 * in documentation (online or textual) provided with the package.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *    must display the following acknowledgement:
 *    "This product includes cryptographic software written by
 *     Eric Young (eay@cryptsoft.com)"
 *    The word 'cryptographic' can be left out if the rouines from the library
 *    being used are not cryptographic related :-).
 * 4. If you include any Windows specific code (or a derivative thereof) from
 *    the apps directory (application code) you must include an acknowledgement:
 *    "This product includes software written by Tim Hudson (tjh@cryptsoft.com)"
 *
 * THIS SOFTWARE IS PROVIDED BY ERIC YOUNG ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 * The licence and distribution terms for any publically available version or
 * derivative of this code cannot be changed.  i.e. this code cannot simply be
 * copied and put under another distribution licence
 * [including the GNU Public Licence.]
 */
/* ====================================================================
 * Copyright (c) 1998-2001 The OpenSSL Project.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in
 *    the documentation and/or other materials provided with the
 *    distribution.
 *
 * 3. All advertising materials mentioning features or use of this
 *    software must display the following acknowledgment:
 *    "This product includes software developed by the OpenSSL Project
 *    for use in the OpenSSL Toolkit. (http://www.openssl.org/)"
 *
 * 4. The names "OpenSSL Toolkit" and "OpenSSL Project" must not be used to
 *    endorse or promote products derived from this software without
 *    prior written permission. For written permission, please contact
 *    openssl-core@openssl.org.
 *
 * 5. Products derived from this software may not be called "OpenSSL"
 *    nor may "OpenSSL" appear in their names without prior written
 *    permission of the OpenSSL Project.
 *
 * 6. Redistributions of any form whatsoever must retain the following
 *    acknowledgment:
 *    "This product includes software developed by the OpenSSL Project
 *    for use in the OpenSSL Toolkit (http://www.openssl.org/)"
 *
 * THIS SOFTWARE IS PROVIDED BY THE OpenSSL PROJECT ``AS IS'' AND ANY
 * EXPRESSED OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE OpenSSL PROJECT OR
 * ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 * ====================================================================
 *
 * This product includes cryptographic software written by Eric Young
 * (eay@cryptsoft.com).  This product includes software written by Tim
 * Hudson (tjh@cryptsoft.com).
 *
 */

#ifndef HEADER_APPS_H
#define HEADER_APPS_H

#include <openssl/opensslconf.h>

#include <openssl/bio.h>
#include <openssl/conf.h>
#include <openssl/lhash.h>
#include <openssl/ossl_typ.h>
#include <openssl/txt_db.h>
#include <openssl/x509.h>
#include <openssl/ui.h>

#ifndef OPENSSL_NO_OCSP
#include <openssl/ocsp.h>
#endif

#include <openssl/ssl.h>

#include <unistd.h>

/* numbers in us */
#define DGRAM_RCV_TIMEOUT         250000
#define DGRAM_SND_TIMEOUT         250000

extern CONF *config;
extern char *default_config_file;
extern BIO *bio_err;

#define PW_MIN_LENGTH 4
typedef struct pw_cb_data {
	const void *password;
	const char *prompt_info;
} PW_CB_DATA;

int password_callback(char *buf, int bufsiz, int verify, void *cb_data);

int setup_ui(void);
void destroy_ui(void);

extern UI_METHOD *ui_method;
int ui_open(UI *ui);
int ui_read(UI *ui, UI_STRING *uis);
int ui_write(UI *ui, UI_STRING *uis);
int ui_close(UI *ui);

int str2fmt(char *s);
void program_name(char *in, char *out, int size);
#ifdef HEADER_X509_H
int dump_cert_text(BIO *out, X509 *x);
void print_name(BIO *out, const char *title, X509_NAME *nm,
    unsigned long lflags);
#endif
int set_cert_ex(unsigned long *flags, const char *arg);
int set_name_ex(unsigned long *flags, const char *arg);
int set_ext_copy(int *copy_type, const char *arg);
int copy_extensions(X509 *x, X509_REQ *req, int copy_type);
int app_passwd(BIO *err, char *arg1, char *arg2, char **pass1, char **pass2);
int add_oid_section(BIO *err, CONF *conf);
X509 *load_cert(BIO *err, const char *file, int format,
    const char *pass, const char *cert_descrip);
EVP_PKEY *load_key(BIO *err, const char *file, int format, int maybe_stdin,
    const char *pass, const char *key_descrip);
EVP_PKEY *load_pubkey(BIO *err, const char *file, int format, int maybe_stdin,
    const char *pass, const char *key_descrip);
STACK_OF(X509) *load_certs(BIO *err, const char *file, int format,
    const char *pass, const char *cert_descrip);
STACK_OF(X509_CRL) *load_crls(BIO *err, const char *file, int format,
    const char *pass, const char *cert_descrip);
X509_STORE *setup_verify(BIO *bp, char *CAfile, char *CApath);

#ifndef OPENSSL_NO_OCSP
OCSP_RESPONSE *process_responder(BIO *err, OCSP_REQUEST *req,
    char *host, char *path, char *port, int use_ssl,
    STACK_OF(CONF_VALUE) *headers, int req_timeout);
#endif

int load_config(BIO *err, CONF *cnf);
char *make_config_name(void);

/* Functions defined in ca.c and also used in ocsp.c */
int unpack_revinfo(ASN1_TIME **prevtm, int *preason, ASN1_OBJECT **phold,
    ASN1_GENERALIZEDTIME **pinvtm, const char *str);

#define DB_type         0
#define DB_exp_date     1
#define DB_rev_date     2
#define DB_serial       3       /* index - unique */
#define DB_file         4
#define DB_name         5       /* index - unique when active and not disabled */
#define DB_NUMBER       6

#define DB_TYPE_REV	'R'
#define DB_TYPE_EXP	'E'
#define DB_TYPE_VAL	'V'
#define DB_TYPE_SUSP	'S'

typedef struct db_attr_st {
	int unique_subject;
} DB_ATTR;
typedef struct ca_db_st {
	DB_ATTR attributes;
	TXT_DB *db;
} CA_DB;

BIGNUM *load_serial(char *serialfile, int create, ASN1_INTEGER **retai);
int save_serial(char *serialfile, char *suffix, BIGNUM *serial,
    ASN1_INTEGER **retai);
int rotate_serial(char *serialfile, char *new_suffix, char *old_suffix);
int rand_serial(BIGNUM *b, ASN1_INTEGER *ai);
CA_DB *load_index(char *dbfile, DB_ATTR *dbattr);
int index_index(CA_DB *db);
int save_index(const char *dbfile, const char *suffix, CA_DB *db);
int rotate_index(const char *dbfile, const char *new_suffix,
    const char *old_suffix);
void free_index(CA_DB *db);
#define index_name_cmp_noconst(a, b) \
	index_name_cmp((const OPENSSL_CSTRING *)CHECKED_PTR_OF(OPENSSL_STRING, a), \
	(const OPENSSL_CSTRING *)CHECKED_PTR_OF(OPENSSL_STRING, b))
int index_name_cmp(const OPENSSL_CSTRING *a, const OPENSSL_CSTRING *b);
int parse_yesno(const char *str, int def);

X509_NAME *parse_name(char *str, long chtype, int multirdn);
int args_verify(char ***pargs, int *pargc, int *badarg, BIO *err,
    X509_VERIFY_PARAM **pm);
int bio_to_mem(unsigned char **out, int maxlen, BIO *in);
int pkey_ctrl_string(EVP_PKEY_CTX *ctx, char *value);
int init_gen_str(BIO *err, EVP_PKEY_CTX **pctx, const char *algname,
    int do_param);
int do_X509_sign(BIO *err, X509 *x, EVP_PKEY *pkey, const EVP_MD *md,
    STACK_OF(OPENSSL_STRING) *sigopts);
int do_X509_REQ_sign(BIO *err, X509_REQ *x, EVP_PKEY *pkey, const EVP_MD *md,
    STACK_OF(OPENSSL_STRING) *sigopts);
int do_X509_CRL_sign(BIO *err, X509_CRL *x, EVP_PKEY *pkey, const EVP_MD *md,
    STACK_OF(OPENSSL_STRING) *sigopts);

unsigned char *next_protos_parse(unsigned short *outlen, const char *in);

#define FORMAT_UNDEF    0
#define FORMAT_ASN1     1
#define FORMAT_TEXT     2
#define FORMAT_PEM      3

#define FORMAT_PKCS12   5
#define FORMAT_SMIME    6

#define FORMAT_PEMRSA	9	/* PEM RSAPublicKey format */
#define FORMAT_ASN1RSA	10	/* DER RSAPublicKey format */
#define FORMAT_MSBLOB	11	/* MS Key blob format */
#define FORMAT_PVK	12	/* MS PVK file format */

#define EXT_COPY_NONE	0
#define EXT_COPY_ADD	1
#define EXT_COPY_ALL	2

#define APP_PASS_LEN	1024

#define SERIAL_RAND_BITS	64

int app_isdir(const char *);

#define TM_RESET	0
#define TM_GET		1
double app_timer_real(int);
double app_timer_user(int);

#define OPENSSL_NO_SSL_INTERN

struct option {
	const char *name;
	const char *argname;
	const char *desc;
	enum {
		OPTION_ARG,
		OPTION_ARGV_FUNC,
		OPTION_ARG_FORMAT,
		OPTION_ARG_FUNC,
		OPTION_ARG_INT,
		OPTION_ARG_LONG,
		OPTION_ARG_TIME,
		OPTION_DISCARD,
		OPTION_FUNC,
		OPTION_FLAG,
		OPTION_FLAG_ORD,
		OPTION_VALUE,
		OPTION_VALUE_AND,
		OPTION_VALUE_OR,
		OPTION_UL_VALUE_OR,
		OPTION_ORDER,
	} type;
	union {
		char **arg;
		int (*argfunc)(char *arg);
		int (*argvfunc)(int argc, char **argv, int *argsused);
		int *flag;
		int (*func)(void);
		long *lvalue;
		int *value;
		unsigned long *ulvalue;
		time_t *tvalue;
		int *order;
	} opt;
	const int value;
	const unsigned long ulvalue;
	int *order;
};

void options_usage(const struct option *opts);
int options_parse(int argc, char **argv, const struct option *opts,
    char **unnamed, int *argsused);

void show_cipher(const OBJ_NAME *name, void *arg);

int asn1parse_main(int argc, char **argv);
int ca_main(int argc, char **argv);
int certhash_main(int argc, char **argv);
int ciphers_main(int argc, char **argv);
int cms_main(int argc, char **argv);
int crl2pkcs7_main(int argc, char **argv);
int crl_main(int argc, char **argv);
int dgst_main(int argc, char **argv);
int dh_main(int argc, char **argv);
int dhparam_main(int argc, char **argv);
int dsa_main(int argc, char **argv);
int dsaparam_main(int argc, char **argv);
int ec_main(int argc, char **argv);
int ecparam_main(int argc, char **argv);
int enc_main(int argc, char **argv);
int errstr_main(int argc, char **argv);
int gendh_main(int argc, char **argv);
int gendsa_main(int argc, char **argv);
int genpkey_main(int argc, char **argv);
int genrsa_main(int argc, char **argv);
int ocsp_main(int argc, char **argv);
int passwd_main(int argc, char **argv);
int pkcs7_main(int argc, char **argv);
int pkcs8_main(int argc, char **argv);
int pkcs12_main(int argc, char **argv);
int pkey_main(int argc, char **argv);
int pkeyparam_main(int argc, char **argv);
int pkeyutl_main(int argc, char **argv);
int prime_main(int argc, char **argv);
int rand_main(int argc, char **argv);
int req_main(int argc, char **argv);
int rsa_main(int argc, char **argv);
int rsautl_main(int argc, char **argv);
int s_client_main(int argc, char **argv);
int s_server_main(int argc, char **argv);
int s_time_main(int argc, char **argv);
int sess_id_main(int argc, char **argv);
int smime_main(int argc, char **argv);
int speed_main(int argc, char **argv);
int ts_main(int argc, char **argv);
int verify_main(int argc, char **argv);
int version_main(int argc, char **argv);
int x509_main(int argc, char **argv);

#define PORT            4433
#define PORT_STR        "4433"
#define PROTOCOL        "tcp"

extern int verify_depth;
extern int verify_return_error;

int do_server(int port, int type, int *ret,
    int (*cb)(int s, unsigned char *context),
    unsigned char *context, int naccept);
int verify_callback(int ok, X509_STORE_CTX *ctx);
int set_cert_stuff(SSL_CTX *ctx, char *cert_file, char *key_file);
int set_cert_key_stuff(SSL_CTX *ctx, X509 *cert, EVP_PKEY *key);
int ssl_print_tmp_key(BIO *out, SSL *s);
int init_client(int *sock, char *server, char *port, int type, int af);
int extract_port(char *str, short *port_ptr);
int extract_host_port(char *str, char **host_ptr, unsigned char *ip, char **p);

long bio_dump_callback(BIO *bio, int cmd, const char *argp, int argi,
    long argl, long ret);

void apps_ssl_info_callback(const SSL *s, int where, int ret);
void msg_cb(int write_p, int version, int content_type, const void *buf,
    size_t len, SSL *ssl, void *arg);
void tlsext_cb(SSL *s, int client_server, int type, unsigned char *data,
    int len, void *arg);

int generate_cookie_callback(SSL *ssl, unsigned char *cookie,
    unsigned int *cookie_len);
int verify_cookie_callback(SSL *ssl, const unsigned char *cookie,
    unsigned int cookie_len);

#endif
