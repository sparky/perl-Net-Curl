/* vim: ts=4:sw=4:ft=xs:fdm=marker: */
/*
 * Copyright 2011 (C) Przemyslaw Iskra <sparky at pld-linux.org>
 *
 * Loosely based on code by Cris Bailiff <c.bailiff+curl at devsecure.com>,
 * and subsequent fixes by other contributors.
 */


typedef enum {
	CB_EASY_WRITE = 0,
	CB_EASY_READ,
	CB_EASY_HEADER,
	CB_EASY_PROGRESS,
	CB_EASY_DEBUG,
	CB_EASY_IOCTL,
	CB_EASY_SEEK,
	CB_EASY_SOCKOPT,
	CB_EASY_OPENSOCKET,
	CB_EASY_INTERLEAVE,
	CB_EASY_CHUNK_BGN,
	CB_EASY_CHUNK_END,
	CB_EASY_FNMATCH,
	CB_EASY_LAST
} perl_curl_easy_callback_code_t;

static const CURLoption perl_curl_easy_option_slist[] = {
	CURLOPT_HTTPHEADER,
	CURLOPT_HTTP200ALIASES,
#ifdef CURLOPT_MAIL_RCPT
	CURLOPT_MAIL_RCPT,
#endif
	CURLOPT_QUOTE,
	CURLOPT_POSTQUOTE,
	CURLOPT_PREQUOTE,
#ifdef CURLOPT_RESOLVE
	CURLOPT_RESOLVE,
#endif
	CURLOPT_TELNETOPTIONS
};
#define perl_curl_easy_option_slist_num \
	sizeof(perl_curl_easy_option_slist) / sizeof(perl_curl_easy_option_slist[0])


struct perl_curl_easy_s {
	/* last seen perl object */
	SV *perl_self;

	/* easy handle */
	CURL *handle;

	/* list of callbacks */
	callback_t cb[ CB_EASY_LAST ];

	/* buffer for error string */
	char errbuf[ CURL_ERROR_SIZE + 1 ];

	/* copies of data for string options */
	simplell_t *strings;

	/* pointers to slists for slist options */
	simplell_t *slists;

	/* parent, if easy is attached to any multi handle */
	perl_curl_multi_t *multi;

	/* if easy is attached to any share object, this will
	 * hold an immortal sv to prevent destruction of share */
	SV *share_sv;

	/* if form is attached to this easy form_sv will hold
	 * an immortal sv to prevent destruction of from */
	SV *form_sv;
};

#include "CurlOO_Easy_callbacks.c"

static long
perl_curl_easy_setoptslist( pTHX_ perl_curl_easy_t *easy, CURLoption option, SV *value,
		int clear )
/*{{{*/ {
	int si = 0;
	AV *array;
	int array_len;
	struct curl_slist **pslist, *slist;

	for ( si = 0; si < perl_curl_easy_option_slist_num; si++ ) {
		if ( perl_curl_easy_option_slist[ si ] == option )
			goto found;
	}
	return -1;

found:

	/* This is an option specifying a list, which we put in a curl_slist struct */
	array = (AV *) SvRV( value );
	array_len = av_len( array );

	/* We have to find out which list to use... */
	pslist = perl_curl_simplell_add( aTHX_ &easy->slists, option );
	slist = *pslist;

	if ( slist && clear ) {
		curl_slist_free_all( slist );
		slist = NULL;
	}

	/* copy perl values into this slist */
	*pslist = slist = perl_curl_array2slist( aTHX_ slist, value );

	/* pass the list into curl_easy_setopt() */
	return curl_easy_setopt( easy->handle, option, slist );
} /*}}}*/

static perl_curl_easy_t *
perl_curl_easy_new( void )
/*{{{*/ {
	perl_curl_easy_t *easy;
	Newxz( easy, 1, perl_curl_easy_t );
	easy->handle = curl_easy_init();
	return easy;
} /*}}}*/

static perl_curl_easy_t *
perl_curl_easy_duphandle( perl_curl_easy_t *orig )
/*{{{*/ {
	perl_curl_easy_t *easy;
	Newxz( easy, 1, perl_curl_easy_t );
	easy->handle = curl_easy_duphandle( orig->handle );
	return easy;
} /*}}}*/

static void
perl_curl_easy_delete_mostly( pTHX_ perl_curl_easy_t *easy )
/*{{{*/ {
	perl_curl_easy_callback_code_t i;

	for ( i = 0; i < CB_EASY_LAST; i++ ) {
		sv_2mortal( easy->cb[i].func );
		sv_2mortal( easy->cb[i].data );
	}

	if ( easy->strings ) {
		simplell_t *next, *now = easy->strings;
		do {
			next = now->next;
			Safefree( now->value );
			Safefree( now );
		} while ( ( now = next ) != NULL );
	}

	if ( easy->slists ) {
		simplell_t *next, *now = easy->slists;
		do {
			next = now->next;
			curl_slist_free_all( now->value );
			Safefree( now );
		} while ( ( now = next ) != NULL );
	}

	if ( easy->form_sv )
		sv_2mortal( easy->form_sv );
} /*}}}*/


static void
perl_curl_easy_delete( pTHX_ perl_curl_easy_t *easy )
/*{{{*/ {

	/* this may trigger a callback,
	 * we want it while easy handle is still alive */
	curl_easy_setopt( easy->handle, CURLOPT_SHARE, NULL );

	if ( easy->handle )
		curl_easy_cleanup( easy->handle );

	perl_curl_easy_delete_mostly( aTHX_ easy );

	if ( easy->share_sv )
		sv_2mortal( easy->share_sv );

	sv_2mortal( easy->perl_self );

	Safefree( easy );

} /*}}}*/

static int
perl_curl_easy_magic_free( pTHX_ SV *sv, MAGIC *mg )
{
	if ( mg->mg_ptr )
		perl_curl_easy_delete( aTHX_ (void *)mg->mg_ptr );
	return 0;
}

static MGVTBL perl_curl_easy_vtbl = {
	NULL, NULL, NULL, NULL
	,perl_curl_easy_magic_free
	,NULL
	,perl_curl_any_magic_nodup
#ifdef MGf_LOCAL
	,NULL
#endif
};

static void
perl_curl_easy_preset( perl_curl_easy_t *easy )
{
	/* configure curl to always callback to the XS interface layer */
	curl_easy_setopt( easy->handle, CURLOPT_WRITEFUNCTION, cb_easy_write );
	curl_easy_setopt( easy->handle, CURLOPT_READFUNCTION, cb_easy_read );

	/* set our own object as the context for all curl callbacks */
	curl_easy_setopt( easy->handle, CURLOPT_FILE, easy );
	curl_easy_setopt( easy->handle, CURLOPT_INFILE, easy );

	/* we always collect this, in case it's wanted */
	curl_easy_setopt( easy->handle, CURLOPT_ERRORBUFFER, easy->errbuf );

	curl_easy_setopt( easy->handle, CURLOPT_PRIVATE, (void *) easy );
}

#define EASY_DIE( ret )			\
	STMT_START {				\
		CURLcode code = (ret);	\
		if ( code != CURLE_OK )	\
			die_code( "Easy", code ); \
	} STMT_END


MODULE = WWW::CurlOO	PACKAGE = WWW::CurlOO::Easy

INCLUDE: const-easy-xs.inc

PROTOTYPES: ENABLE

void
new( sclass="WWW::CurlOO::Easy", base=HASHREF_BY_DEFAULT )
	const char *sclass
	SV *base
	PREINIT:
		perl_curl_easy_t *easy;
		HV *stash;
	PPCODE:
		if ( ! SvOK( base ) || ! SvROK( base ) )
			croak( "object base must be a valid reference\n" );

		easy = perl_curl_easy_new();
		perl_curl_easy_preset( easy );

		perl_curl_setptr( aTHX_ base, &perl_curl_easy_vtbl, easy );
		stash = gv_stashpv( sclass, 0 );
		ST(0) = sv_bless( base, stash );

		easy->perl_self = newSVsv( ST(0) );
		sv_rvweaken( easy->perl_self );

		XSRETURN(1);


void
duphandle( easy, base=HASHREF_BY_DEFAULT )
	WWW::CurlOO::Easy easy
	SV *base
	PREINIT:
		perl_curl_easy_t *clone;
		const char *sclass;
		perl_curl_easy_callback_code_t i;
		HV *stash;
	PPCODE:
		if ( ! SvOK( base ) || ! SvROK( base ) )
			croak( "object base must be a valid reference\n" );

		sclass = sv_reftype( SvRV( ST(0) ), TRUE );
		clone = perl_curl_easy_duphandle( easy );

		perl_curl_easy_preset( clone );

		if ( easy->cb[ CB_EASY_HEADER ].func
				|| easy->cb[ CB_EASY_HEADER ].data ) {
			curl_easy_setopt( clone->handle, CURLOPT_HEADERFUNCTION, cb_easy_header );
			curl_easy_setopt( clone->handle, CURLOPT_WRITEHEADER, clone );
		}

		if ( easy->cb[ CB_EASY_PROGRESS ].func
				|| easy->cb[ CB_EASY_PROGRESS ].data ) {
			curl_easy_setopt( clone->handle, CURLOPT_PROGRESSFUNCTION, cb_easy_progress );
			curl_easy_setopt( clone->handle, CURLOPT_PROGRESSDATA, clone );
		}

		if ( easy->cb[ CB_EASY_DEBUG ].func ) {
			curl_easy_setopt( clone->handle, CURLOPT_DEBUGFUNCTION, cb_easy_debug );
			curl_easy_setopt( clone->handle, CURLOPT_DEBUGDATA, clone );
		}

		for( i = 0; i < CB_EASY_LAST; i++ ) {
			SvREPLACE( clone->cb[i].func, easy->cb[i].func );
			SvREPLACE( clone->cb[i].data, easy->cb[i].data );
		};

		/* clone strings and set */
		if ( easy->strings ) {
			simplell_t *in, **out;
			in = easy->strings;
			out = &clone->strings;
			do {
				Newx( *out, 1, simplell_t );
				(*out)->next = NULL;
				(*out)->key = in->key;
				(*out)->value = savepv( in->value );

				curl_easy_setopt( clone->handle, in->key, (*out)->value );
				out = &(*out)->next;
				in = in->next;
			} while ( in != NULL );
		}

		/* clone slists and set */
		if ( easy->slists ) {
			simplell_t *in, **out;
			struct curl_slist *sin, *sout;
			in = easy->slists;
			out = &clone->slists;
			do {
				Newx( *out, 1, simplell_t );
				sout = NULL;
				sin = in->value;
				do {
					sout = curl_slist_append( sout, sin->data );
				} while ( ( sin = sin->next ) != NULL );

				(*out)->next = NULL;
				(*out)->key = in->key;
				(*out)->value = sout;

				curl_easy_setopt( clone->handle, in->key, (*out)->value );
				out = &(*out)->next;
				in = in->next;
			} while ( in != NULL );
		}

		if ( easy->share_sv ) {
			perl_curl_share_t *share;
			share = perl_curl_getptr( aTHX_ easy->share_sv,
				&perl_curl_share_vtbl );

			clone->share_sv = newSVsv( easy->share_sv );
			curl_easy_setopt( clone->handle, CURLOPT_SHARE, share->handle );
		}

		if ( easy->form_sv ) {
			perl_curl_form_t *form;
			form = perl_curl_getptr( aTHX_ easy->form_sv,
				&perl_curl_form_vtbl );

			clone->form_sv = newSVsv( easy->form_sv );
			curl_easy_setopt( clone->handle, CURLOPT_HTTPPOST, form->post );
		}

		perl_curl_setptr( aTHX_ base, &perl_curl_easy_vtbl, clone );
		stash = gv_stashpv( sclass, 0 );
		ST(0) = sv_bless( base, stash );

		clone->perl_self = newSVsv( ST(0) );
		sv_rvweaken( clone->perl_self );

		XSRETURN(1);


void
reset( easy )
	WWW::CurlOO::Easy easy
	CODE:
		perl_curl_easy_delete_mostly( aTHX_ easy );
		perl_curl_easy_preset( easy );


void
setopt( easy, option, value )
	WWW::CurlOO::Easy easy
	int option
	SV *value
	PREINIT:
		int opttype;
	CODE:
		opttype = option - option % CURLOPTTYPE_OBJECTPOINT;
		if ( opttype == CURLOPTTYPE_LONG ) {
			perl_curl_easy_setopt_long( aTHX_ easy, option, value );
		} else if ( opttype == CURLOPTTYPE_OBJECTPOINT ) {
			perl_curl_easy_setopt_object( aTHX_ easy, option, value );
		} else if ( opttype == CURLOPTTYPE_FUNCTIONPOINT ) {
			perl_curl_easy_setopt_function( aTHX_ easy, option, value );
		} else if ( opttype == CURLOPTTYPE_OFF_T ) {
			perl_curl_easy_setopt_off_t( aTHX_ easy, option, value );
		} else {
			croak( "invalid option %d", option );
		}


void
perform( easy )
	WWW::CurlOO::Easy easy
	PREINIT:
		CURLcode ret;
	CODE:
		CLEAR_ERRSV();
		ret = curl_easy_perform( easy->handle );

		/* rethrow errors */
		if ( SvTRUE( ERRSV ) )
			croak( NULL );

		EASY_DIE( ret );


SV *
getinfo( easy, option )
	WWW::CurlOO::Easy easy
	int option
	CODE:
		switch ( option & CURLINFO_TYPEMASK ) {
			case CURLINFO_STRING:
			{
				CURLcode ret;
				char * vchar;
				ret = curl_easy_getinfo( easy->handle, option, &vchar );
				EASY_DIE( ret );
				RETVAL = newSVpv( vchar, 0 );
				break;
			}
			case CURLINFO_LONG:
			{
				CURLcode ret;
				long vlong;
				ret = curl_easy_getinfo( easy->handle, option, &vlong );
				EASY_DIE( ret );
				RETVAL = newSViv( vlong );
				break;
			}
			case CURLINFO_DOUBLE:
			{
				CURLcode ret;
				double vdouble;
				ret = curl_easy_getinfo( easy->handle, option, &vdouble );
				EASY_DIE( ret );
				RETVAL = newSVnv( vdouble );
				break;
			}
			case CURLINFO_SLIST:
			{
				CURLcode ret;
				struct curl_slist *vlist, *entry;
				AV *items = NULL;
				ret = curl_easy_getinfo( easy->handle, option, &vlist );
				EASY_DIE( ret );

				if ( vlist != NULL ) {
					items = newAV();
					entry = vlist;
					while ( entry ) {
						av_push( items, newSVpv( entry->data, 0 ) );
						entry = entry->next;
					}
					curl_slist_free_all( vlist );
				}
				RETVAL = newRV( sv_2mortal( (SV *) items ) );
				break;
			}
			default: {
				croak( "invalid getinfo option" );
				break;
			}
		}
	OUTPUT:
		RETVAL


#if LIBCURL_VERSION_NUM >= 0x071200

void
pause( easy, bitmask )
	WWW::CurlOO::Easy easy
	int bitmask
	CODE:
		CURLcode ret;
		ret = curl_easy_pause( easy, bitmask );
		EASY_DIE( ret );

#endif

#if LIBCURL_VERSION_NUM >= 0x071202

size_t
send( easy, buffer )
	WWW::CurlOO::Easy easy
	SV *buffer
	CODE:
		CURLcode ret;
		STRLEN len;
		const char *pv;
		size_t out_len;

		if ( ! SvOK( buffer ) )
			croak( "buffer is not valid\n" );

		pv = SvPV( buffer, len );
		ret = curl_easy_send( easy->handle, pv, len, &out_len );
		EASY_DIE( ret );

		RETVAL = out_len;
	OUTPUT:
		RETVAL


size_t
recv( easy, buffer, length )
	WWW::CurlOO::Easy easy
	SV *buffer
	size_t length
	CODE:
		CURLcode ret;
		size_t out_len;
		char *tmpbuf;

		if ( !SvOK( buffer ) )
			sv_setpvn( buffer, "", 0 );

		if ( !SvPOK( buffer ) ) {
			SvPV_nolen( buffer );
			if ( !SvPOK( buffer ) )
				croak( "internal WWW::CurlOO error" );
		}

		Sv_Grow( buffer, SvCUR( buffer ) + length + 1 );

		tmpbuf = SvEND( buffer );

		ret = curl_easy_recv( easy->handle, tmpbuf, length, &out_len );
		EASY_DIE( ret );

		SvCUR_set( buffer, SvCUR( buffer ) + out_len );

		RETVAL = out_len;
	OUTPUT:
		RETVAL

#endif


SV *
strerror( ... )
	PROTOTYPE: $;$
	PREINIT:
		const char *errstr;
	CODE:
		if ( items < 1 || items > 2 )
			croak( "Usage: WWW::CurlOO::Easy::strerror( [easy], errnum )" );
		errstr = curl_easy_strerror( SvIV( ST( items - 1 ) ) );
		RETVAL = newSVpv( errstr, 0 );
	OUTPUT:
		RETVAL


# /* Extensions: Functions that do not have libcurl equivalents. */


void
pushopt( easy, option, value )
	WWW::CurlOO::Easy easy
	int option
	SV *value
	PREINIT:
		CURLcode ret;
	CODE:
		ret = perl_curl_easy_setoptslist( aTHX_ easy, option, value, 0 );
		if ( ret < 0 )
			ret = CURLE_BAD_FUNCTION_ARGUMENT;
		EASY_DIE( ret );


char *
error( easy )
	WWW::CurlOO::Easy easy
	CODE:
		RETVAL = easy->errbuf;
	OUTPUT:
		RETVAL


SV *
multi( easy )
	WWW::CurlOO::Easy easy
	CODE:
		RETVAL = easy->multi ? newSVsv( easy->multi->perl_self ) : &PL_sv_undef;
	OUTPUT:
		RETVAL


SV *
share( easy )
	WWW::CurlOO::Easy easy
	CODE:
		RETVAL = easy->share_sv ? newSVsv( easy->share_sv ) : &PL_sv_undef;
	OUTPUT:
		RETVAL


SV *
form( easy )
	WWW::CurlOO::Easy easy
	CODE:
		RETVAL = easy->form_sv ? newSVsv( easy->form_sv ) : &PL_sv_undef;
	OUTPUT:
		RETVAL


int
CLONE_SKIP( pkg )
	SV *pkg
	CODE:
		(void ) pkg;
		RETVAL = 1;
	OUTPUT:
		RETVAL
