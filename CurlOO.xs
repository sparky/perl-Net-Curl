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
#include "const-defenums-h.inc"

#ifndef Newx
# define Newx(v,n,t)	New(0,v,n,t)
# define Newxc(v,n,t,c)	Newc(0,v,n,t,c)
# define Newxz(v,n,t)	Newz(0,v,n,t)
#endif

#ifndef hv_stores
# define hv_stores(hv,key,val) hv_store( hv, key, sizeof( key ) - 1, val, 0 )
#endif

#ifndef CLEAR_ERRSV
# define CLEAR_ERRSV()					\
	STMT_START {						\
		sv_setpvn( ERRSV, "", 0 );		\
		if ( SvMAGICAL( ERRSV ) )		\
			mg_free( ERRSV );			\
		SvPOK_only( ERRSV );			\
	} STMT_END
#endif

#ifndef croak_sv
# define croak_sv( arg )		\
	STMT_START {				\
		SvSetSV( ERRSV, arg );	\
		croak( NULL );			\
	} STMT_END
#endif

#define die_code( pkg, num )			\
	STMT_START {						\
		SV *errsv = sv_newmortal();		\
		sv_setref_iv( errsv, "WWW::CurlOO::" pkg "::Code", num ); \
		croak_sv( errsv );				\
	} STMT_END


#ifndef mPUSHs
# define mPUSHs( sv ) PUSHs( sv_2mortal( sv ) )
#endif
#ifndef mXPUSHs
# define mXPUSHs( sv ) XPUSHs( sv_2mortal( sv ) )
#endif
#ifndef PTR2nat
# define PTR2nat(p)	(PTRV)(p)
#endif

/*
 * Convenient way to copy SVs
 */
#define SvREPLACE( dst, src ) \
	STMT_START {						\
		SV *src_ = (src);				\
		if ( dst )						\
			sv_2mortal( dst );			\
		if ( (src_) && SvOK( src_ ) )	\
			dst = newSVsv( src_ );		\
		else							\
			dst = NULL;					\
	} STMT_END


typedef struct {
	/* function that will be called */
	SV *func;

	/* user data */
	SV *data;
} callback_t;

typedef struct perl_curl_easy_s perl_curl_easy_t;
typedef struct perl_curl_form_s perl_curl_form_t;
typedef struct perl_curl_share_s perl_curl_share_t;
typedef struct perl_curl_multi_s perl_curl_multi_t;

static struct curl_slist *
perl_curl_array2slist( pTHX_ struct curl_slist *slist, SV *arrayref )
{
	AV *array;
	int array_len, i;

	if ( !SvOK( arrayref ) || !SvROK( arrayref ) )
		croak( "not an array" );

	array = (AV *) SvRV( arrayref );
	array_len = av_len( array );

	for ( i = 0; i <= array_len; i++ ) {
		SV **sv;
		char *string;

		sv = av_fetch( array, i, 0 );
		if ( !SvOK( *sv ) )
			continue;
		string = SvPV_nolen( *sv );
		slist = curl_slist_append( slist, string );
	}

	return slist;
}

typedef struct simplell_s simplell_t;
struct simplell_s {
	/* next in the linked list */
	simplell_t *next;

	/* curl option it belongs to */
	PTRV key;

	/* the actual data */
	void *value;
};

#if 0
static void *
perl_curl_simplell_get( pTHX_ simplell_t *start, PTRV key )
{
	simplell_t *now = start;

	if ( now == NULL )
		return NULL;

	while ( now ) {
		if ( now->key == key )
			return &(now->value);
		if ( now->key > key )
			return NULL;
		now = now->next;
	}

	return NULL;
}
#endif


static void *
perl_curl_simplell_add( pTHX_ simplell_t **start, PTRV key )
{
	simplell_t **now = start;
	simplell_t *tmp = NULL;

	while ( *now ) {
		if ( (*now)->key == key )
			return &( (*now)->value );
		if ( (*now)->key > key )
			break;
		now = &( (*now)->next );
	}

	tmp = *now;
	Newx( *now, 1, simplell_t );
	(*now)->next = tmp;
	(*now)->key = key;
	(*now)->value = NULL;

	return &( (*now)->value );
}

static void *
perl_curl_simplell_del( pTHX_ simplell_t **start, PTRV key )
{
	simplell_t **now = start;

	while ( *now ) {
		if ( (*now)->key == key ) {
			void *ret = (*now)->value;
			simplell_t *tmp = *now;
			*now = (*now)->next;
			Safefree( tmp );
			return ret;
		}
		if ( (*now)->key > key )
			return NULL;
		now = &( (*now)->next );
	}
	return NULL;
}

/* generic function for our callback calling needs */
static IV
perl_curl_call( pTHX_ callback_t *cb, int argnum, SV **args )
{
	dSP;
	int i;
	IV status;
	SV *olderrsv = NULL;
	int method_call = 0;

	if ( ! cb->func || ! SvOK( cb->func ) ) {
		warn( "callback function is not set\n" );
		return -1;
	} else if ( SvROK( cb->func ) )
		method_call = 0;
	else if ( SvPOK( cb->func ) )
		method_call = 1;
	else {
		warn( "Don't know how to call the callback\n" );
		return -1;
	}

	ENTER;
	SAVETMPS;

	PUSHMARK( SP );

	EXTEND( SP, argnum );
	for ( i = 0; i < argnum; i++ )
		mPUSHs( args[ i ] );

	if ( cb->data )
		mXPUSHs( newSVsv( cb->data ) );

	PUTBACK;

	if ( SvTRUE( ERRSV ) )
		olderrsv = sv_2mortal( newSVsv( ERRSV ) );

	if ( method_call )
		call_method( SvPV_nolen( cb->func ), G_SCALAR | G_EVAL );
	else
		call_sv( cb->func, G_SCALAR | G_EVAL );

	SPAGAIN;

	if ( SvTRUE( ERRSV ) ) {
		/* cleanup after the error */
		(void) POPs;
		status = -1;
	} else {
		status = POPi;
	}

	if ( olderrsv )
		sv_setsv( ERRSV, olderrsv );

	PUTBACK;
	FREETMPS;
	LEAVE;

	return status;
}

#define PERL_CURL_CALL( cb, arg ) \
	perl_curl_call( aTHX_ (cb), sizeof( arg ) / sizeof( (arg)[0] ), (arg) )


static int
perl_curl_any_magic_nodup( pTHX_ MAGIC *mg, CLONE_PARAMS *param )
{
	warn( "WWW::CurlOO::(Easy|Form|Multi) does not support cloning\n" );
	mg->mg_ptr = NULL;
	return 1;
}

static void *
perl_curl_getptr( pTHX_ SV *self, MGVTBL *vtbl )
{
	MAGIC *mg;

	if ( !self )
		return NULL;

	if ( !SvOK( self ) )
		return NULL;

	if ( !SvROK( self ) )
		return NULL;

	if ( !sv_isobject( self ) )
		return NULL;

	for ( mg = SvMAGIC( SvRV( self ) ); mg != NULL; mg = mg->mg_moremagic ) {
		if ( mg->mg_type == PERL_MAGIC_ext && mg->mg_virtual == vtbl )
			return mg->mg_ptr;
	}

	return NULL;
}


static void *
perl_curl_getptr_fatal( pTHX_ SV *self, MGVTBL *vtbl, const char *name,
		const char *type )
{
	void *ret;
	SV **perl_self;

	if ( ! sv_derived_from( self, type ) )
		croak( "'%s' is not a %s object", name, type );

	ret = perl_curl_getptr( aTHX_ self, vtbl );

	if ( ret == NULL )
		croak( "'%s' is an invalid %s object", name, type );

	/*
	 * keep alive: this trick makes sure user will not destroy last
	 * existing reference from inside of a callback.
	 */
	perl_self = ret;
	sv_2mortal( newSVsv( *perl_self ) );

	return ret;
}


static void
perl_curl_setptr( pTHX_ SV *self, MGVTBL *vtbl, void *ptr )
{
	MAGIC *mg;

	if ( perl_curl_getptr( aTHX_ self, vtbl ) )
		croak( "object already has our pointer" );

	mg = sv_magicext( SvRV( self ), 0, PERL_MAGIC_ext,
		vtbl, (const char *) ptr, 0 );
	mg->mg_flags |= MGf_DUP;
}


/* code shamelessly stolen from ExtUtils::Constant */
static void
perl_curl_constant_add( pTHX_ HV *hash, const char *name, I32 namelen,
		SV *value )
{
#if PERL_REVISION == 5 && PERL_VERSION >= 9
	SV **sv = hv_fetch( hash, name, namelen, TRUE );
	if ( !sv )
		croak( "Could not add key '%s' to %%WWW::CurlOO::", name );

	if ( SvOK( *sv ) || SvTYPE( *sv ) == SVt_PVGV ) {
		newCONSTSUB( hash, name, value );
	} else {
		SvUPGRADE( *sv, SVt_RV );
		SvRV_set( *sv, value );
		SvROK_on( *sv );
		SvREADONLY_on( value );
	}
#else
	newCONSTSUB( hash, (char *)name, value );
#endif
}

struct iv_s {
	const char *name;
	I32 namelen;
	IV value;
};
#define IV_CONST( c ) \
	{ #c, sizeof( #c ) - 1, c }
struct pv_s {
	const char *name;
	I32 namelen;
	const char *value;
	I32 valuelen;
};
#define PV_CONST( c ) \
	{ #c, sizeof( #c ) - 1, c, sizeof( c ) - 1 }


typedef perl_curl_easy_t *WWW__CurlOO__Easy;
typedef perl_curl_form_t *WWW__CurlOO__Form;
typedef perl_curl_multi_t *WWW__CurlOO__Multi;
typedef perl_curl_share_t *WWW__CurlOO__Share;

/* default base object */
#define HASHREF_BY_DEFAULT		newRV_noinc( sv_2mortal( (SV *) newHV() ) )

#include "curloo-Easy-c.inc"
#include "curloo-Form-c.inc"
#include "curloo-Multi-c.inc"
#include "curloo-Share-c.inc"
#include "CurlOO_Easy_setopt.c"

MODULE = WWW::CurlOO	PACKAGE = WWW::CurlOO

BOOT:
	{
		/* XXX 1: this is _not_ thread safe */
		/* XXX 2: should never be called from a thread */
		static int run_once = 0;
		if ( !run_once++ )
			curl_global_init( CURL_GLOBAL_ALL );
	}
	{
		dTHX;
		HV *symbol_table = get_hv( "WWW::CurlOO::", GV_ADD );
		static const struct iv_s values_for_iv[] = {
			IV_CONST( LIBCURL_VERSION_MAJOR ),
			IV_CONST( LIBCURL_VERSION_MINOR ),
			IV_CONST( LIBCURL_VERSION_PATCH ),
			IV_CONST( LIBCURL_VERSION_NUM ),
			{ NULL, 0, 0 }
		};
		static const struct pv_s values_for_pv[] = {
			PV_CONST( LIBCURL_COPYRIGHT ),
			PV_CONST( LIBCURL_VERSION ),
			PV_CONST( LIBCURL_TIMESTAMP ),
			{ NULL, 0, NULL, 0 }
		};
		const struct iv_s *value_for_iv = values_for_iv;
		const struct pv_s *value_for_pv = values_for_pv;
		while ( value_for_iv->name ) {
			perl_curl_constant_add( aTHX_ symbol_table,
				value_for_iv->name, value_for_iv->namelen,
				newSViv( value_for_iv->value ) );
			++value_for_iv;
		}
		while ( value_for_pv->name ) {
			perl_curl_constant_add( aTHX_ symbol_table,
				value_for_pv->name, value_for_pv->namelen,
				newSVpvn( value_for_pv->value, value_for_pv->valuelen ) );
			++value_for_pv;
		}


		++PL_sub_generation;
	}

PROTOTYPES: ENABLE

INCLUDE: const-curl-xs.inc

void
_global_cleanup()
	CODE:
		curl_global_cleanup();

time_t
getdate( timedate )
	char *timedate
	CODE:
		RETVAL = curl_getdate( timedate, NULL );
	OUTPUT:
		RETVAL

char *
version()
	CODE:
		RETVAL = curl_version();
	OUTPUT:
		RETVAL


SV *
version_info()
	PREINIT:
		const curl_version_info_data *vi;
		HV *ret;
	CODE:
		/* {{{ */
		vi = curl_version_info( CURLVERSION_NOW );
		if ( vi == NULL )
			croak( "curl_version_info() returned NULL\n" );
		ret = newHV();

		(void) hv_stores( ret, "age", newSViv( vi->age ) );
		if ( vi->age >= CURLVERSION_FIRST ) {
			if ( vi->version )
				(void) hv_stores( ret, "version", newSVpv( vi->version, 0 ) );
			(void) hv_stores( ret, "version_num", newSVuv( vi->version_num ) );
			if ( vi->host )
				(void) hv_stores( ret, "host", newSVpv( vi->host, 0 ) );
			(void) hv_stores( ret, "features", newSViv( vi->features ) );
			if ( vi->ssl_version )
				(void) hv_stores( ret, "ssl_version", newSVpv( vi->ssl_version, 0 ) );
			(void) hv_stores( ret, "ssl_version_num", newSViv( vi->ssl_version_num ) );
			if ( vi->libz_version )
				(void) hv_stores( ret, "libz_version", newSVpv( vi->libz_version, 0 ) );
			if ( vi->protocols ) {
				const char * const *p = vi->protocols;
				AV *prot;
				prot = (AV *) sv_2mortal( (SV *) newAV() );
				while ( *p != NULL ) {
					av_push( prot, newSVpv( *p, 0 ) );
					p++;
				}

				(void) hv_stores( ret, "protocols", newRV( (SV*) prot ) );
			}
		}
		if ( vi->age >= CURLVERSION_SECOND ) {
			if ( vi->ares )
				(void) hv_stores( ret, "ares", newSVpv( vi->ares, 0 ) );
			(void) hv_stores( ret, "ares_num", newSViv( vi->ares_num ) );
		}
		if ( vi->age >= CURLVERSION_THIRD ) {
			if ( vi->libidn )
				(void) hv_stores( ret, "libidn", newSVpv( vi->libidn, 0 ) );
		}
#ifdef CURLVERSION_FOURTH
		if ( vi->age >= CURLVERSION_FOURTH ) {
			(void) hv_stores( ret, "iconv_ver_num", newSViv( vi->iconv_ver_num ) );
			if ( vi->libssh_version )
				(void) hv_stores( ret, "libssh_version", newSVpv( vi->libssh_version, 0 ) );
		}
#endif

		RETVAL = newRV( (SV *) ret );
		/* }}} */
	OUTPUT:
		RETVAL


INCLUDE: curloo-Easy-xs.inc
INCLUDE: curloo-Form-xs.inc
INCLUDE: curloo-Multi-xs.inc
INCLUDE: curloo-Share-xs.inc
