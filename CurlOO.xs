/* vim: ts=4:sw=4:fdm=marker: */

/*
 * Perl interface for libcurl. Check out the file README for more info.
 */

/*
 * Copyright (C) 2000, 2001, 2002, 2005, 2008 Daniel Stenberg, Cris Bailiff, et al.
 * Copyright (C) 2011 Przemyslaw Iskra.
 * You may opt to use, copy, modify, merge, publish, distribute and/or
 * sell copies of the Software, and permit persons to whom the
 * Software is furnished to do so, under the terms of the MPL or
 * the MIT/X-derivate licenses. You may pick one of these licenses.
 */
#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <curl/curl.h>
#include <curl/easy.h>
#include <curl/multi.h>
#include "const-defenums.h"
#include "const-c.inc"

#ifndef Newx
# define Newx(v,n,t)    New(0,v,n,t)
# define Newxc(v,n,t,c) Newc(0,v,n,t,c)
# define Newxz(v,n,t)   Newz(0,v,n,t)
#endif

#ifndef hv_stores
# define hv_stores(hv,key,val) hv_store( hv, key, sizeof( key ) - 1, val, 0 )
#endif

typedef enum {
	CALLBACK_WRITE = 0,
	CALLBACK_READ,
	CALLBACK_HEADER,
	CALLBACK_PROGRESS,
	CALLBACK_DEBUG,
	CALLBACK_LAST
} perl_curl_easy_callback_code_t;

typedef enum {
	SLIST_HTTPHEADER = 0,
	SLIST_HTTP200ALIASES,
	SLIST_MAIL_RCPT,
	SLIST_QUOTE,
	SLIST_POSTQUOTE,
	SLIST_PREQUOTE,
	SLIST_RESOLVE,
	SLIST_TELNETOPTIONS,
	SLIST_LAST
} perl_curl_easy_slist_code_t;

typedef struct {
	/* function that will be called */
	SV *func;

	/* user data */
	SV *data;
} callback_t;

typedef struct perl_curl_multi_s perl_curl_multi_t;
typedef struct perl_curl_share_s perl_curl_share_t;
typedef struct perl_curl_form_s perl_curl_form_t;

typedef struct {
	/* last seen version of this object */
	SV *perl_self;

	/* The main curl handle */
	CURL *curl;

	/* Lists that can be set via curl_easy_setopt() */
	I32 *y;
	struct curl_slist *slist[ SLIST_LAST ];

	/* list of callbacks */
	callback_t cb[ CALLBACK_LAST ];

	/* copy of error buffer var for caller*/
	char errbuf[CURL_ERROR_SIZE+1];
	char *errbufvarname;

	I32 strings_index;
	char *strings[ CURLOPT_LASTENTRY % CURLOPTTYPE_OBJECTPOINT ];

	/* parent, if easy is attached to any multi object */
	perl_curl_multi_t *multi;

	/* if easy is attached to any share object */
	perl_curl_share_t *share;
} perl_curl_easy_t;


typedef enum {
	CALLBACKM_SOCKET = 0,
	CALLBACKM_TIMER,
	CALLBACKM_LAST,
} perl_curl_multi_callback_code_t;

struct perl_curl_multi_s {
	/* last seen version of this object */
	SV *perl_self;

	/* curl multi handle */
	CURLM *curlm;

	/* list of callbacks */
	callback_t cb[ CALLBACKM_LAST ];
};

typedef enum {
	CALLBACKSH_LOCK = 0,
	CALLBACKSH_UNLOCK,
	CALLBACKSH_LAST,
} perl_curl_share_callback_code_t;

struct perl_curl_share_s {
	/* last seen version of this object */
	SV *perl_self;

	/* curl share handle */
	CURLSH *curlsh;

	/* list of callbacks */
	callback_t cb[ CALLBACKSH_LAST ];
};


/* switch from curl option codes to the relevant callback index */
static perl_curl_easy_callback_code_t
callback_index( int option )
/*{{{*/ {
	switch( option ) {
		case CURLOPT_WRITEFUNCTION:
		case CURLOPT_FILE:
			return CALLBACK_WRITE;
			break;

		case CURLOPT_READFUNCTION:
		case CURLOPT_INFILE:
			return CALLBACK_READ;
			break;

		case CURLOPT_HEADERFUNCTION:
		case CURLOPT_WRITEHEADER:
			return CALLBACK_HEADER;
			break;

		case CURLOPT_PROGRESSFUNCTION:
		case CURLOPT_PROGRESSDATA:
			return CALLBACK_PROGRESS;
			break;
		case CURLOPT_DEBUGFUNCTION:
		case CURLOPT_DEBUGDATA:
			return CALLBACK_DEBUG;
			break;
	}
	croak("Bad callback index requested\n");
	return CALLBACK_LAST;
} /*}}}*/


static int
perl_curl_easy_setoptslist( pTHX_ perl_curl_easy_t *self, CURLoption option, SV *value,
		int clear )
/*{{{*/ {
	perl_curl_easy_slist_code_t si = 0;
	AV *array;
	int array_len;
	struct curl_slist **slist = NULL;
	int i;

	switch( option ) {
		case CURLOPT_HTTPHEADER:
			si = SLIST_HTTPHEADER;
			break;
		case CURLOPT_HTTP200ALIASES:
			si = SLIST_HTTP200ALIASES;
			break;
#ifdef CURLOPT_MAIL_RCPT
		case CURLOPT_MAIL_RCPT:
			si = SLIST_MAIL_RCPT;
			break;
#endif
		case CURLOPT_QUOTE:
			si = SLIST_QUOTE;
			break;
		case CURLOPT_POSTQUOTE:
			si = SLIST_POSTQUOTE;
			break;
		case CURLOPT_PREQUOTE:
			si = SLIST_PREQUOTE;
			break;
#ifdef CURLOPT_RESOLVE
		case CURLOPT_RESOLVE:
			si = SLIST_RESOLVE;
			break;
#endif
		case CURLOPT_TELNETOPTIONS:
			si = SLIST_TELNETOPTIONS;
			break;
		default:
			return -1;
	}


	/* This is an option specifying a list, which we put in a curl_slist struct */
	array = (AV *)SvRV( value );
	array_len = av_len( array );

	/* We have to find out which list to use... */
	slist = &( self->slist[ si ] );

	if ( *slist && clear ) {
		curl_slist_free_all( *slist );
		*slist = NULL;
	}

	/* copy perl values into this slist */
	for ( i = 0; i <= array_len; i++ ) {
		SV **sv = av_fetch( array, i, 0 );
		STRLEN len = 0;
		char *string = SvPV( *sv, len );
		if ( len == 0 ) /* FIXME: is this correct? */
			continue;
		*slist = curl_slist_append( *slist, string );
	}

	/* pass the list into curl_easy_setopt() */
	return curl_easy_setopt(self->curl, option, *slist);
} /*}}}*/

static perl_curl_easy_t *
perl_curl_easy_new( void )
/*{{{*/ {
	perl_curl_easy_t *self;
	Newxz( self, 1, perl_curl_easy_t );
	self->curl=curl_easy_init();
	return self;
} /*}}}*/

static perl_curl_easy_t *
perl_curl_easy_duphandle( perl_curl_easy_t *orig )
/*{{{*/ {
	perl_curl_easy_t *self;
	Newxz( self, 1, perl_curl_easy_t );
	self->curl=curl_easy_duphandle(orig->curl);
	return self;
} /*}}}*/

static void
perl_curl_easy_update( perl_curl_easy_t *self, SV *perl_self )
/*{{{*/{
	self->perl_self = perl_self;
	curl_easy_setopt( self->curl, CURLOPT_PRIVATE, (void *)self );
}/*}}}*/

static void
perl_curl_easy_delete( pTHX_ perl_curl_easy_t *self )
/*{{{*/ {
	perl_curl_easy_slist_code_t index;
	perl_curl_easy_callback_code_t i;

	if ( self->curl )
		curl_easy_cleanup( self->curl );

	*self->y = *self->y - 1;
	if (*self->y <= 0) {
		for ( index = 0; index < SLIST_LAST; index++ ) {
			if (self->slist[index])
				curl_slist_free_all( self->slist[index] );
		}
		Safefree(self->y);
	}

	for ( i = 0; i < CALLBACK_LAST; i++ ) {
		sv_2mortal( self->cb[i].func );
		sv_2mortal( self->cb[i].data );
	}

	if ( self->errbufvarname )
		free( self->errbufvarname );

	for ( i = 0; i <= self->strings_index; i++ ) {
		if ( self->strings[ i ] != NULL ) {
			char* ptr = self->strings[i];
			Safefree(ptr);
		}
	}
	Safefree(self);

} /*}}}*/

/* Register a callback function */

static void
perl_curl_easy_register_callback( pTHX_ perl_curl_easy_t *self, SV **callback, SV *function )
/*{{{*/ {
	if (function && SvOK(function)) {
		/* FIXME: need to check the ref-counts here */
		if (*callback == NULL) {
			*callback = newSVsv(function);
		} else {
			SvSetSV(*callback, function);
		}
	} else {
		if (*callback != NULL) {
			sv_2mortal(*callback);
			*callback = NULL;
		}
	}
} /*}}}*/

static void
perl_curl_multi_register_callback( pTHX_ perl_curl_multi_t *self, SV **callback, SV *function )
/*{{{*/ {
	if (function && SvOK(function)) {
		/* FIXME: need to check the ref-counts here */
		if (*callback == NULL) {
			*callback = newSVsv(function);
		} else {
			SvSetSV(*callback, function);
		}
	} else {
		if (*callback != NULL) {
			sv_2mortal(*callback);
			*callback = NULL;
		}
	}
} /*}}}*/

static void
perl_curl_share_register_callback( pTHX_ perl_curl_share_t *self, SV **callback, SV *function )
/*{{{*/ {
	if (function && SvOK(function)) {
		/* FIXME: need to check the ref-counts here */
		if (*callback == NULL) {
			*callback = newSVsv(function);
		} else {
			SvSetSV(*callback, function);
		}
	} else {
		if (*callback != NULL) {
			sv_2mortal(*callback);
			*callback = NULL;
		}
	}
} /*}}}*/


/* make a new multi */
static perl_curl_multi_t *
perl_curl_multi_new( void )
/*{{{*/ {
	perl_curl_multi_t *self;
	Newxz( self, 1, perl_curl_multi_t );
	self->curlm=curl_multi_init();
	return self;
} /*}}}*/

/* delete the multi */
static void
perl_curl_multi_delete( pTHX_ perl_curl_multi_t *self )
/*{{{*/ {
	perl_curl_multi_callback_code_t i;

	if (self->curlm)
		curl_multi_cleanup(self->curlm);

	for(i=0;i<CALLBACKM_LAST;i++) {
		sv_2mortal(self->cb[i].func);
		sv_2mortal(self->cb[i].data);
	}

	Safefree(self);
} /*}}}*/

/* make a new share */
static perl_curl_share_t *
perl_curl_share_new( void )
/*{{{*/ {
	perl_curl_share_t *self;
	Newxz( self, 1, perl_curl_share_t );
	self->curlsh=curl_share_init();
	return self;
} /*}}}*/

/* delete the share */
static void
perl_curl_share_delete( pTHX_ perl_curl_share_t *self )
/*{{{*/ {
	perl_curl_share_callback_code_t i;
	if (self->curlsh)
		curl_share_cleanup(self->curlsh);

	for(i=0;i<CALLBACKSH_LAST;i++) {
		sv_2mortal(self->cb[i].func);
		sv_2mortal(self->cb[i].data);
	}
	Safefree(self);
} /*}}}*/

static size_t
write_to_ctx( pTHX_ SV* const call_ctx, const char* const ptr, size_t const n )
/*{{{*/ {
	PerlIO *handle;
	SV* out_str;
	if (call_ctx) { /* a GLOB or a SCALAR ref */
		if(SvROK(call_ctx) && SvTYPE(SvRV(call_ctx)) <= SVt_PVMG) {
			/* write to a scalar ref */
			out_str = SvRV(call_ctx);
			if (SvOK(out_str)) {
				sv_catpvn(out_str, ptr, n);
			} else {
				sv_setpvn(out_str, ptr, n);
			}
			return n;
		}
		else {
			/* write to a filehandle */
			handle = IoOFP(sv_2io(call_ctx));
		}
	} else { /* punt to stdout */
		handle = PerlIO_stdout();
	}
	return PerlIO_write(handle, ptr, n);
} /*}}}*/

/* generic fwrite callback, which decides which callback to call */
static size_t
fwrite_wrapper( const void *ptr, size_t size, size_t nmemb,
		perl_curl_easy_t *self, SV *call_function, SV *call_ctx)
/*{{{*/ {
	dTHX;
	if (call_function) { /* We are doing a callback to perl */
		dSP;
		int count, status;

		ENTER;
		SAVETMPS;

		PUSHMARK(SP);

		/* $easy, $buffer, $userdata */
		XPUSHs( sv_2mortal( newSVsv( self->perl_self ) ) );

		if (ptr) {
			XPUSHs(sv_2mortal(newSVpvn((char *)ptr, (STRLEN)(size * nmemb))));
		} else { /* just in case */
			XPUSHs(&PL_sv_undef);
		}
		if (call_ctx) {
			XPUSHs(sv_2mortal(newSVsv(call_ctx)));
		} else { /* should be a stdio glob ? */
			XPUSHs(&PL_sv_undef);
		}

		PUTBACK;
		count = perl_call_sv( call_function, G_SCALAR );
		SPAGAIN;

		if (count != 1)
			croak("callback for CURLOPT_WRITEFUNCTION didn't return a status\n");

		status = POPi;

		PUTBACK;
		FREETMPS;
		LEAVE;
		return status;

	} else {
		return write_to_ctx(aTHX_ call_ctx, ptr, size * nmemb);
	}
} /*}}}*/

/* debug fwrite callback */
static size_t
fwrite_wrapper2( const void *ptr, size_t size, perl_curl_easy_t *self,
		SV *call_function, SV *call_ctx, curl_infotype type )
/*{{{*/ {
	dTHX;
	dSP;

	if (call_function) { /* We are doing a callback to perl */
		int count, status;
		SV *sv;

		ENTER;
		SAVETMPS;

		PUSHMARK(SP);

		/* $easy, $type, $buffer, $userdata */
		XPUSHs( sv_2mortal( newSVsv( self->perl_self ) ) );

		XPUSHs( sv_2mortal( newSViv( type ) ) );

		if (ptr) {
			XPUSHs(sv_2mortal(newSVpvn((char *)ptr, (STRLEN)(size * sizeof(char)))));
		} else { /* just in case */
			XPUSHs(&PL_sv_undef);
		}

		if (call_ctx) {
			XPUSHs(sv_2mortal(newSVsv(call_ctx)));
		} else { /* should be a stdio glob ? */
			XPUSHs(&PL_sv_undef);
		}

		PUTBACK;
		count = perl_call_sv(call_function, G_SCALAR);
		SPAGAIN;

		if (count != 1)
			croak("callback for CURLOPT_*FUNCTION didn't return a status\n");

		status = POPi;

		PUTBACK;
		FREETMPS;
		LEAVE;
		return status;

	} else {
		return write_to_ctx(aTHX_ call_ctx, ptr, size * sizeof(char));
	}
} /*}}}*/

/* Write callback for calling a perl callback */
static size_t
cb_easy_write( const void *ptr, size_t size, size_t nmemb, void *userptr )
/*{{{*/ {
	perl_curl_easy_t *self;
	self=(perl_curl_easy_t *)userptr;
	return fwrite_wrapper( ptr, size, nmemb, self,
			self->cb[CALLBACK_WRITE].func, self->cb[CALLBACK_WRITE].data );
} /*}}}*/

/* header callback for calling a perl callback */
static size_t
cb_easy_header( const void *ptr, size_t size, size_t nmemb,
		void *userptr )
/*{{{*/ {
	perl_curl_easy_t *self;
	self=(perl_curl_easy_t *)userptr;

	return fwrite_wrapper( ptr, size, nmemb, self,
			self->cb[CALLBACK_HEADER].func, self->cb[CALLBACK_HEADER].data );
} /*}}}*/

/* debug callback for calling a perl callback */
static int
cb_easy_debug( CURL* handle, curl_infotype type, char *ptr, size_t size,
		void *userptr )
/*{{{*/ {
	perl_curl_easy_t *self;
	self=(perl_curl_easy_t *)userptr;

	return fwrite_wrapper2( ptr, size, self,
			self->cb[CALLBACK_DEBUG].func, self->cb[CALLBACK_DEBUG].data, type);
} /*}}}*/

/* read callback for calling a perl callback */
static size_t
cb_easy_read( void *ptr, size_t size, size_t nmemb, void *userptr )
/*{{{*/ {
	dTHX;
	dSP ;

	size_t maxlen;
	perl_curl_easy_t *self;
	self=(perl_curl_easy_t *)userptr;

	maxlen = size*nmemb;

	if (self->cb[CALLBACK_READ].func) { /* We are doing a callback to perl */
		char *data;
		int count;
		SV *sv;
		STRLEN len;

		ENTER ;
		SAVETMPS ;

		PUSHMARK(SP) ;

		if (self->cb[CALLBACK_READ].data) {
			sv = self->cb[CALLBACK_READ].data;
		} else {
			sv = &PL_sv_undef;
		}

		/* $easy, $maxsize, $userdata */
		XPUSHs( sv_2mortal( newSVsv( self->perl_self ) ) );
		XPUSHs( sv_2mortal( newSViv( maxlen ) ) );
		XPUSHs( sv_2mortal( newSVsv( sv ) ) );

		PUTBACK ;
		count = perl_call_sv( self->cb[CALLBACK_READ].func, G_SCALAR );
		SPAGAIN;

		if (count != 1)
			croak("callback for CURLOPT_READFUNCTION didn't return any data\n");

		sv = POPs;
		data = SvPV(sv,len);

		/* only allowed to return the number of bytes asked for */
		len = (len<maxlen ? len : maxlen);
		/* memcpy(ptr,data,(size_t)len); */
		Copy( data, ptr, len, char );

		PUTBACK ;
		FREETMPS ;
		LEAVE ;
		return (size_t) (len/size);

	} else {
		/* read input directly */
		PerlIO *f;
		if (self->cb[CALLBACK_READ].data) { /* hope its a GLOB! */
			f = IoIFP(sv_2io(self->cb[CALLBACK_READ].data));
		} else { /* punt to stdin */
			f = PerlIO_stdin();
		}
		return PerlIO_read(f,ptr,maxlen);
	}
} /*}}}*/

/* Progress callback for calling a perl callback */

static int
cb_easy_progress( void *userptr, double dltotal, double dlnow,
		double ultotal, double ulnow )
/*{{{*/ {
	dTHX;
	dSP;

	int count;
	perl_curl_easy_t *self;
	self=(perl_curl_easy_t *)userptr;

	ENTER;
	SAVETMPS;
	PUSHMARK(sp);

	/* $easy, $dltotal, $dlnow, $ultotal, $ulnow, $userdata */
	XPUSHs( sv_2mortal( newSVsv( self->perl_self ) ) );
	XPUSHs( sv_2mortal( newSVnv( dltotal ) ) );
	XPUSHs( sv_2mortal( newSVnv( dlnow ) ) );
	XPUSHs( sv_2mortal( newSVnv( ultotal ) ) );
	XPUSHs( sv_2mortal( newSVnv( ulnow ) ) );
	if ( self->cb[CALLBACK_PROGRESS].data ) {
		XPUSHs( sv_2mortal( newSVsv( self->cb[CALLBACK_PROGRESS].data ) ) );
	} else {
		XPUSHs( &PL_sv_undef );
	}

	PUTBACK;
	count = perl_call_sv(self->cb[CALLBACK_PROGRESS].func, G_SCALAR);
	SPAGAIN;

	if (count != 1)
		croak("callback for CURLOPT_PROGRESSFUNCTION didn't return 1\n");

	count = POPi;

	PUTBACK;
	FREETMPS;
	LEAVE;
	return count;
} /*}}}*/


static void
cb_share_lock( CURL *easy, curl_lock_data data, curl_lock_access locktype,
		void *userptr )
/*{{{*/ {
	dTHX;
	dSP;

	int count;
	perl_curl_share_t *self;
	perl_curl_easy_t *peasy;

	self=(perl_curl_share_t *)userptr;
	(void) curl_easy_getinfo( easy, CURLINFO_PRIVATE, (void *)&peasy);

	ENTER;
	SAVETMPS;
	PUSHMARK(sp);

	/* $easy, $data, $locktype, $userdata */
	XPUSHs( sv_2mortal( newSVsv( peasy->perl_self ) ) );
	XPUSHs( sv_2mortal( newSViv( data ) ) );
	XPUSHs( sv_2mortal( newSViv( locktype ) ) );
	if (self->cb[CALLBACKSH_LOCK].data) {
		XPUSHs(sv_2mortal(newSVsv(self->cb[CALLBACKSH_LOCK].data)));
	} else {
		XPUSHs(&PL_sv_undef);
	}

	PUTBACK;
	count = perl_call_sv( self->cb[CALLBACKSH_LOCK].func, G_SCALAR );
	SPAGAIN;

	if (count != 0)
		croak("callback for CURLSHOPT_LOCKFUNCTION didn't return void\n");

	PUTBACK;
	FREETMPS;
	LEAVE;
	return;
} /*}}}*/

static void
cb_share_unlock( CURL *easy, curl_lock_data data, void *userptr )
/*{{{*/ {
	dTHX;
	dSP;

	int count;
	perl_curl_share_t *self;
	perl_curl_easy_t *peasy;

	self=(perl_curl_share_t *)userptr;
	(void) curl_easy_getinfo( easy, CURLINFO_PRIVATE, (void *)&peasy);

	ENTER;
	SAVETMPS;
	PUSHMARK(sp);

	/* $easy, $data, $userdata */
	XPUSHs( sv_2mortal( newSVsv( peasy->perl_self ) ) );
	XPUSHs( sv_2mortal( newSViv( data ) ) );
	if (self->cb[CALLBACKSH_LOCK].data) {
		XPUSHs(sv_2mortal(newSVsv(self->cb[CALLBACKSH_LOCK].data)));
	} else {
		XPUSHs(&PL_sv_undef);
	}

	PUTBACK;
	count = perl_call_sv( self->cb[CALLBACKSH_LOCK].func, G_SCALAR );
	SPAGAIN;

	if (count != 0)
		croak("callback for CURLSHOPT_UNLOCKFUNCTION didn't return void\n");

	PUTBACK;
	FREETMPS;
	LEAVE;
	return;
} /*}}}*/

static int
cb_multi_socket( CURL *easy, curl_socket_t s, int what, void *userptr,
		void *socketp )
/*{{{*/ {
	dTHX;
	dSP;

	int count;
	perl_curl_multi_t *self;
	perl_curl_easy_t *peasy;

	self=(perl_curl_multi_t *)userptr;
	(void) curl_easy_getinfo( easy, CURLINFO_PRIVATE, (void *)&peasy);

	ENTER;
	SAVETMPS;
	PUSHMARK(sp);

	/* $easy, $socket, $what, $userdata */
	/* XXX: add $socketdata */
	XPUSHs( sv_2mortal( newSVsv( peasy->perl_self ) ) );
	XPUSHs(sv_2mortal(newSVuv( s )));
	XPUSHs(sv_2mortal(newSViv( what )));
	if (self->cb[CALLBACKM_SOCKET].data) {
		XPUSHs(sv_2mortal(newSVsv(self->cb[CALLBACKM_SOCKET].data)));
	} else {
		XPUSHs(&PL_sv_undef);
	}

	PUTBACK;
	count = perl_call_sv(self->cb[CALLBACKM_SOCKET].func, G_SCALAR);
	SPAGAIN;

	if (count != 1)
		croak("callback for CURLMOPT_SOCKETFUNCTION didn't return 1\n");

	count = POPi;

	PUTBACK;
	FREETMPS;
	LEAVE;
	return count;
} /*}}}*/

static int
cb_multi_timer( CURLM *multi, long timeout_ms, void *userptr )
/*{{{*/ {
	dTHX;
	dSP;

	int count;
	perl_curl_multi_t *self;
	self=(perl_curl_multi_t *)userptr;

	ENTER;
	SAVETMPS;
	PUSHMARK(sp);

	/* $multi, $timeout, $userdata */
	XPUSHs( sv_2mortal( newSVsv( self->perl_self ) ) );
	XPUSHs( sv_2mortal( newSViv( timeout_ms ) ) );
	if ( self->cb[CALLBACKM_TIMER].data )
		XPUSHs( sv_2mortal( newSVsv( self->cb[CALLBACKM_TIMER].data ) ) );

	PUTBACK;
	count = perl_call_sv( self->cb[CALLBACKM_TIMER].func, G_SCALAR );
	SPAGAIN;

	if (count != 1)
		croak("callback for CURLMOPT_TIMERFUNCTION didn't return 1\n");

	count = POPi;

	PUTBACK;
	FREETMPS;
	LEAVE;
	return count;
} /*}}}*/

static const MGVTBL perl_curl_vtbl = { NULL };

static void
perl_curl_setptr( pTHX_ SV *self, void *ptr )
{
	MAGIC *mg;

	mg = sv_magicext (SvRV (self), 0, PERL_MAGIC_ext, &perl_curl_vtbl, (const char *)ptr, 0);
	mg->mg_flags |= MGf_DUP;
}

static void *
perl_curl_getptr( pTHX_ SV *self )
{
	MAGIC *mg;

	if ( !self )
		croak( "self is null\n" );

	if ( !SvOK( self ) )
		croak( "self not OK\n" );

	if ( !SvROK( self ) )
		croak( "self not ROK\n" );

	if ( !sv_isobject( self ) )
		croak( "self is not an object" );

	for (mg = SvMAGIC( SvRV( self ) ); mg; mg = mg->mg_moremagic ) {
		if ( mg->mg_type == PERL_MAGIC_ext && mg->mg_virtual == &perl_curl_vtbl )
			return mg->mg_ptr;
	}

	croak( "object does not have required pointer" );
}

typedef perl_curl_easy_t *WWW__CurlOO__Easy;
typedef perl_curl_form_t *WWW__CurlOO__Form;
typedef perl_curl_multi_t *WWW__CurlOO__Multi;
typedef perl_curl_share_t *WWW__CurlOO__Share;

/* default base object */
#define HASHREF_BY_DEFAULT		newRV_noinc( sv_2mortal( (SV *)newHV() ) )

#include "CurlOO_Form.xs"
#define XS_SECTION

MODULE = WWW::CurlOO	PACKAGE = WWW::CurlOO		PREFIX = curl_

BOOT:
	curl_global_init(CURL_GLOBAL_ALL); /* FIXME: does this need a mutex for ithreads? */

PROTOTYPES: ENABLE

INCLUDE: const-curl-xs.inc

void
curl__global_cleanup()
	CODE:
		curl_global_cleanup();

time_t
curl_getdate( timedate )
	char *timedate
	CODE:
		RETVAL = curl_getdate( timedate, NULL );
	OUTPUT:
		RETVAL

char *
curl_version()
	CODE:
		RETVAL = curl_version();
	OUTPUT:
		RETVAL


SV *
curl_version_info()
	PREINIT:
		const curl_version_info_data *vi;
		HV *ret;
	CODE:
		/* {{{ */
		vi = curl_version_info( CURLVERSION_NOW );
		if ( vi == NULL )
			croak( "curl_version_info() returned NULL\n" );
		ret = newHV();

		hv_stores( ret, "age", newSViv(vi->age) );
		if ( vi->age >= CURLVERSION_FIRST ) {
			if ( vi->version )
				hv_stores( ret, "version", newSVpv(vi->version, 0) );
			hv_stores( ret, "version_num", newSVuv(vi->version_num) );
			if ( vi->host )
				hv_stores( ret, "host", newSVpv(vi->host, 0) );
			hv_stores( ret, "features", newSViv(vi->features) );
			if ( vi->ssl_version )
				hv_stores( ret, "ssl_version", newSVpv(vi->ssl_version, 0) );
			hv_stores( ret, "ssl_version_num", newSViv(vi->ssl_version_num) );
			if ( vi->libz_version )
				hv_stores( ret, "libz_version", newSVpv(vi->libz_version, 0) );
			if ( vi->protocols ) {
				const char * const *p = vi->protocols;
				AV *prot;
				prot = (AV *)sv_2mortal((SV *)newAV());
				while ( *p != NULL ) {
					av_push( prot, newSVpv( *p, 0 ) );
					p++;
				}

				hv_stores( ret, "protocols", newRV((SV*)prot) );
			}
		}
		if ( vi->age >= CURLVERSION_SECOND ) {
			if ( vi->ares )
				hv_stores( ret, "ares", newSVpv(vi->ares, 0) );
			hv_stores( ret, "ares_num", newSViv(vi->ares_num) );
		}
		if ( vi->age >= CURLVERSION_THIRD ) {
			if ( vi->libidn )
				hv_stores( ret, "libidn", newSVpv(vi->libidn, 0) );
		}
#ifdef CURLVERSION_FOURTH
		if ( vi->age >= CURLVERSION_FOURTH ) {
			hv_stores( ret, "iconv_ver_num", newSViv(vi->iconv_ver_num) );
			if ( vi->libssh_version )
				hv_stores( ret, "libssh_version", newSVpv(vi->libssh_version, 0) );
		}
#endif

		RETVAL = newRV( (SV *)ret );
		/* }}} */
	OUTPUT:
		RETVAL


INCLUDE: CurlOO_Easy.xs
INCLUDE: grep XS_SECTION -A10000 CurlOO_Form.xs |
INCLUDE: CurlOO_Multi.xs
INCLUDE: CurlOO_Share.xs
