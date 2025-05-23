/* $OpenBSD: rc4.c,v 1.13 2025/01/27 14:02:32 jsing Exp $ */
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

#include <endian.h>

#include <openssl/rc4.h>

#include "crypto_arch.h"

/* RC4 as implemented from a posting from
 * Newsgroups: sci.crypt
 * From: sterndark@netcom.com (David Sterndark)
 * Subject: RC4 Algorithm revealed.
 * Message-ID: <sternCvKL4B.Hyy@netcom.com>
 * Date: Wed, 14 Sep 1994 06:35:31 GMT
 */

#ifdef HAVE_RC4_INTERNAL
void rc4_internal(RC4_KEY *key, size_t len, const unsigned char *indata,
    unsigned char *outdata);

#else
static void
rc4_internal(RC4_KEY *key, size_t len, const unsigned char *indata,
    unsigned char *outdata)
{
	RC4_INT *d;
	RC4_INT x, y,tx, ty;
	size_t i;

	x = key->x;
	y = key->y;
	d = key->data;

#if defined(RC4_CHUNK)
	/*
	 * The original reason for implementing this(*) was the fact that
	 * pre-21164a Alpha CPUs don't have byte load/store instructions
	 * and e.g. a byte store has to be done with 64-bit load, shift,
	 * and, or and finally 64-bit store. Peaking data and operating
	 * at natural word size made it possible to reduce amount of
	 * instructions as well as to perform early read-ahead without
	 * suffering from RAW (read-after-write) hazard. This resulted
	 * in ~40%(**) performance improvement on 21064 box with gcc.
	 * But it's not only Alpha users who win here:-) Thanks to the
	 * early-n-wide read-ahead this implementation also exhibits
	 * >40% speed-up on SPARC and 20-30% on 64-bit MIPS (depending
	 * on sizeof(RC4_INT)).
	 *
	 * (*)	"this" means code which recognizes the case when input
	 *	and output pointers appear to be aligned at natural CPU
	 *	word boundary
	 * (**)	i.e. according to 'apps/openssl speed rc4' benchmark,
	 *	crypto/rc4/rc4speed.c exhibits almost 70% speed-up...
	 *
	 * Caveats.
	 *
	 * - RC4_CHUNK="unsigned long long" should be a #1 choice for
	 *   UltraSPARC. Unfortunately gcc generates very slow code
	 *   (2.5-3 times slower than one generated by Sun's WorkShop
	 *   C) and therefore gcc (at least 2.95 and earlier) should
	 *   always be told that RC4_CHUNK="unsigned long".
	 *
	 *					<appro@fy.chalmers.se>
	 */

# define RC4_STEP	( \
			x=(x+1) &0xff,	\
			tx=d[x],	\
			y=(tx+y)&0xff,	\
			ty=d[y],	\
			d[y]=tx,	\
			d[x]=ty,	\
			(RC4_CHUNK)d[(tx+ty)&0xff]\
			)

	if ((((size_t)indata & (sizeof(RC4_CHUNK) - 1)) |
	    ((size_t)outdata & (sizeof(RC4_CHUNK) - 1))) == 0 ) {
		RC4_CHUNK ichunk, otp;

		/*
		 * I reckon we can afford to implement both endian
		 * cases and to decide which way to take at run-time
		 * because the machine code appears to be very compact
		 * and redundant 1-2KB is perfectly tolerable (i.e.
		 * in case the compiler fails to eliminate it:-). By
		 * suggestion from Terrel Larson <terr@terralogic.net>.
		 *
		 * Special notes.
		 *
		 * - compilers (those I've tried) don't seem to have
		 *   problems eliminating either the operators guarded
		 *   by "if (sizeof(RC4_CHUNK)==8)" or the condition
		 *   expressions themselves so I've got 'em to replace
		 *   corresponding #ifdefs from the previous version;
		 * - I chose to let the redundant switch cases when
		 *   sizeof(RC4_CHUNK)!=8 be (were also #ifdefed
		 *   before);
		 * - in case you wonder "&(sizeof(RC4_CHUNK)*8-1)" in
		 *   [LB]ESHFT guards against "shift is out of range"
		 *   warnings when sizeof(RC4_CHUNK)!=8
		 *
		 *			<appro@fy.chalmers.se>
		 */
#if BYTE_ORDER == BIG_ENDIAN
# define BESHFT(c)	(((sizeof(RC4_CHUNK)-(c)-1)*8)&(sizeof(RC4_CHUNK)*8-1))
		for (; len & (0 - sizeof(RC4_CHUNK)); len -= sizeof(RC4_CHUNK)) {
			ichunk  = *(RC4_CHUNK *)indata;
			otp = RC4_STEP << BESHFT(0);
			otp |= RC4_STEP << BESHFT(1);
			otp |= RC4_STEP << BESHFT(2);
			otp |= RC4_STEP << BESHFT(3);
			if (sizeof(RC4_CHUNK) == 8) {
				otp |= RC4_STEP << BESHFT(4);
				otp |= RC4_STEP << BESHFT(5);
				otp |= RC4_STEP << BESHFT(6);
				otp |= RC4_STEP << BESHFT(7);
			}
			*(RC4_CHUNK *)outdata = otp^ichunk;
			indata += sizeof(RC4_CHUNK);
			outdata += sizeof(RC4_CHUNK);
		}
#else
# define LESHFT(c)	(((c)*8)&(sizeof(RC4_CHUNK)*8-1))
		for (; len & (0 - sizeof(RC4_CHUNK)); len -= sizeof(RC4_CHUNK)) {
			ichunk = *(RC4_CHUNK *)indata;
			otp = RC4_STEP;
			otp |= RC4_STEP << 8;
			otp |= RC4_STEP << 16;
			otp |= RC4_STEP << 24;
			if (sizeof(RC4_CHUNK) == 8) {
				otp |= RC4_STEP << LESHFT(4);
				otp |= RC4_STEP << LESHFT(5);
				otp |= RC4_STEP << LESHFT(6);
				otp |= RC4_STEP << LESHFT(7);
			}
			*(RC4_CHUNK *)outdata = otp ^ ichunk;
			indata += sizeof(RC4_CHUNK);
			outdata += sizeof(RC4_CHUNK);
		}
#endif
	}
#endif
#define RC4_LOOP(in,out) \
		x=((x+1)&0xff); \
		tx=d[x]; \
		y=(tx+y)&0xff; \
		d[x]=ty=d[y]; \
		d[y]=tx; \
		(out) = d[(tx+ty)&0xff]^ (in);

	i = len >> 3;
	if (i) {
		for (;;) {
			RC4_LOOP(indata[0], outdata[0]);
			RC4_LOOP(indata[1], outdata[1]);
			RC4_LOOP(indata[2], outdata[2]);
			RC4_LOOP(indata[3], outdata[3]);
			RC4_LOOP(indata[4], outdata[4]);
			RC4_LOOP(indata[5], outdata[5]);
			RC4_LOOP(indata[6], outdata[6]);
			RC4_LOOP(indata[7], outdata[7]);

			indata += 8;
			outdata += 8;

			if (--i == 0)
				break;
		}
	}
	i = len&0x07;
	if (i) {
		for (;;) {
			RC4_LOOP(indata[0], outdata[0]);
			if (--i == 0)
				break;
			RC4_LOOP(indata[1], outdata[1]);
			if (--i == 0)
				break;
			RC4_LOOP(indata[2], outdata[2]);
			if (--i == 0)
				break;
			RC4_LOOP(indata[3], outdata[3]);
			if (--i == 0)
				break;
			RC4_LOOP(indata[4], outdata[4]);
			if (--i == 0)
				break;
			RC4_LOOP(indata[5], outdata[5]);
			if (--i == 0)
				break;
			RC4_LOOP(indata[6], outdata[6]);
			if (--i == 0)
				break;
		}
	}
	key->x = x;
	key->y = y;
}
#endif

#ifdef HAVE_RC4_SET_KEY_INTERNAL
void rc4_set_key_internal(RC4_KEY *key, int len, const unsigned char *data);

#else
static inline void
rc4_set_key_internal(RC4_KEY *key, int len, const unsigned char *data)
{
	RC4_INT tmp;
	int id1, id2;
	RC4_INT *d;
	unsigned int i;

	d = &(key->data[0]);
	key->x = 0;
	key->y = 0;
	id1 = id2 = 0;

#define SK_LOOP(d,n) { \
		tmp=d[(n)]; \
		id2 = (data[id1] + tmp + id2) & 0xff; \
		if (++id1 == len) id1=0; \
		d[(n)]=d[id2]; \
		d[id2]=tmp; }

	for (i = 0; i < 256; i++)
		d[i] = i;
	for (i = 0; i < 256; i += 4) {
		SK_LOOP(d, i + 0);
		SK_LOOP(d, i + 1);
		SK_LOOP(d, i + 2);
		SK_LOOP(d, i + 3);
	}
}
#endif

void
RC4(RC4_KEY *key, size_t len, const unsigned char *indata,
    unsigned char *outdata)
{
	rc4_internal(key, len, indata, outdata);
}
LCRYPTO_ALIAS(RC4);

void
RC4_set_key(RC4_KEY *key, int len, const unsigned char *data)
{
	rc4_set_key_internal(key, len, data);
}
LCRYPTO_ALIAS(RC4_set_key);
