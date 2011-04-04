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
	/* last seen version of this object */
	SV *perl_self;

	/* The main curl handle */
	CURL *handle;

	/* list of callbacks */
	callback_t cb[ CB_EASY_LAST ];

	/* copy of error buffer var for caller*/
	char errbuf[CURL_ERROR_SIZE+1];
	char *errbufvarname;

	optionll_t *strings;

	/* Lists that can be set via curl_easy_setopt() */
	optionll_t *slists;

	/* parent, if easy is attached to any multi object */
	perl_curl_multi_t *multi;

	/* if easy is attached to any share object */
	SV *share_sv;

	/* if easy is attached to any form object */
	SV *form_sv;
};



/* switch from curl option codes to the relevant callback index */
static perl_curl_easy_callback_code_t
callback_index( int option )
/*{{{*/ {
	switch( option ) {
		case CURLOPT_WRITEFUNCTION:
		case CURLOPT_FILE:
			return CB_EASY_WRITE;
			break;

		case CURLOPT_READFUNCTION:
		case CURLOPT_INFILE:
			return CB_EASY_READ;
			break;

		case CURLOPT_HEADERFUNCTION:
		case CURLOPT_WRITEHEADER:
			return CB_EASY_HEADER;
			break;

		case CURLOPT_PROGRESSFUNCTION:
		case CURLOPT_PROGRESSDATA:
			return CB_EASY_PROGRESS;
			break;
		case CURLOPT_DEBUGFUNCTION:
		case CURLOPT_DEBUGDATA:
			return CB_EASY_DEBUG;
			break;
	}
	croak( "Bad callback index requested\n" );
	return CB_EASY_LAST;
} /*}}}*/


static int
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
	return CURLE_BAD_FUNCTION_ARGUMENT;

found:

	/* This is an option specifying a list, which we put in a curl_slist struct */
	array = (AV *) SvRV( value );
	array_len = av_len( array );

	/* We have to find out which list to use... */
	pslist = perl_curl_optionll_add( aTHX_ &easy->slists, option );
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
perl_curl_easy_update( perl_curl_easy_t *easy, SV *perl_self )
/*{{{*/{
	easy->perl_self = perl_self;
	curl_easy_setopt( easy->handle, CURLOPT_PRIVATE, (void *) easy );
}/*}}}*/

static void
perl_curl_easy_delete( pTHX_ perl_curl_easy_t *easy )
/*{{{*/ {
	perl_curl_easy_callback_code_t i;

	if ( easy->handle )
		curl_easy_cleanup( easy->handle );

	for ( i = 0; i < CB_EASY_LAST; i++ ) {
		sv_2mortal( easy->cb[i].func );
		sv_2mortal( easy->cb[i].data );
	}

	if ( easy->errbufvarname )
		free( easy->errbufvarname );

	if ( easy->strings ) {
		optionll_t *next, *now = easy->strings;
		do {
			next = now->next;
			Safefree( now->data );
			Safefree( now );
		} while ( ( now = next ) != NULL );
	}

	if ( easy->slists ) {
		optionll_t *next, *now = easy->slists;
		do {
			next = now->next;
			curl_slist_free_all( now->data );
			Safefree( now );
		} while ( ( now = next ) != NULL );
	}

	if ( easy->form_sv )
		sv_2mortal( easy->form_sv );

	if ( easy->share_sv )
		sv_2mortal( easy->share_sv );

	Safefree( easy );

} /*}}}*/

/* Register a callback function */

static void
perl_curl_easy_register_callback( pTHX_ perl_curl_easy_t *easy, SV **callback,
		SV *function )
/*{{{*/ {
	if ( function && SvOK( function ) ) {
		/* FIXME: need to check the ref-counts here */
		if ( *callback == NULL ) {
			*callback = newSVsv( function );
		} else {
			SvSetSV( *callback, function );
		}
	} else {
		if ( *callback != NULL ) {
			sv_2mortal( *callback );
			*callback = NULL;
		}
	}
} /*}}}*/

static size_t
write_to_ctx( pTHX_ SV* const call_ctx, const char* const ptr, size_t const n )
/*{{{*/ {
	PerlIO *handle;
	SV* out_str;
	if ( call_ctx ) { /* a GLOB or a SCALAR ref */
		if( SvROK( call_ctx ) && SvTYPE( SvRV( call_ctx ) ) <= SVt_PVMG ) {
			/* write to a scalar ref */
			out_str = SvRV( call_ctx );
			if ( SvOK( out_str ) ) {
				sv_catpvn( out_str, ptr, n );
			} else {
				sv_setpvn( out_str, ptr, n );
			}
			return n;
		}
		else {
			/* write to a filehandle */
			handle = IoOFP( sv_2io( call_ctx ) );
		}
	} else { /* punt to stdout */
		handle = PerlIO_stdout();
	}
	return PerlIO_write( handle, ptr, n );
} /*}}}*/

/* generic fwrite callback, which decides which callback to call */
static size_t
fwrite_wrapper( const void *ptr, size_t size, size_t nmemb,
		perl_curl_easy_t *easy, SV *call_function, SV *call_ctx )
/*{{{*/ {
	dTHX;
	if ( call_function ) { /* We are doing a callback to perl */
		SV *args[] = {
			newSVsv( easy->perl_self ),
			ptr
				? newSVpvn( (char *) ptr, (STRLEN) (size * nmemb) )
				: newSVsv( &PL_sv_undef ),
			NULL
		};
		int argn = 2;

		if ( call_ctx )
			args[ argn++ ] = newSVsv( call_ctx );

		return perl_curl_call( aTHX_ call_function, argn, args );
	} else {
		return write_to_ctx( aTHX_ call_ctx, ptr, size * nmemb );
	}
} /*}}}*/

/* debug fwrite callback */
static size_t
fwrite_wrapper2( const void *ptr, size_t size, perl_curl_easy_t *easy,
		SV *call_function, SV *call_ctx, curl_infotype type )
/*{{{*/ {
	dTHX;

	if ( call_function ) { /* We are doing a callback to perl */
		SV *args[] = {
			newSVsv( easy->perl_self ),
			newSViv( type ),
			ptr
				? newSVpvn( (char *) ptr, (STRLEN) (size) )
				: newSVsv( &PL_sv_undef ),
			NULL
		};
		int argn = 3;

		if ( call_ctx )
			args[ argn++ ] = newSVsv( call_ctx );

		return perl_curl_call( aTHX_ call_function, argn, args );
	} else {
		return write_to_ctx( aTHX_ call_ctx, ptr, size * sizeof(char) );
	}
} /*}}}*/

/* Write callback for calling a perl callback */
static size_t
cb_easy_write( const void *ptr, size_t size, size_t nmemb, void *userptr )
/*{{{*/ {
	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	return fwrite_wrapper( ptr, size, nmemb, easy,
			easy->cb[CB_EASY_WRITE].func, easy->cb[CB_EASY_WRITE].data );
} /*}}}*/

/* header callback for calling a perl callback */
static size_t
cb_easy_header( const void *ptr, size_t size, size_t nmemb,
		void *userptr )
/*{{{*/ {
	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;

	return fwrite_wrapper( ptr, size, nmemb, easy,
			easy->cb[CB_EASY_HEADER].func, easy->cb[CB_EASY_HEADER].data );
} /*}}}*/

/* debug callback for calling a perl callback */
static int
cb_easy_debug( CURL* handle, curl_infotype type, char *ptr, size_t size,
		void *userptr )
/*{{{*/ {
	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;

	return fwrite_wrapper2( ptr, size, easy,
			easy->cb[CB_EASY_DEBUG].func, easy->cb[CB_EASY_DEBUG].data, type );
} /*}}}*/

/* read callback for calling a perl callback */
static size_t
cb_easy_read( void *ptr, size_t size, size_t nmemb, void *userptr )
/*{{{*/ {
	dTHX;
	dSP;

	size_t maxlen;
	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;

	maxlen = size*nmemb;

	if ( easy->cb[CB_EASY_READ].func ) { /* We are doing a callback to perl */
		char *data;
		SV *sv;
		STRLEN len;
		size_t status;

		ENTER;
		SAVETMPS;

		PUSHMARK( SP );

		/* $easy, $maxsize, $userdata */
		mXPUSHs( newSVsv( easy->perl_self ) );
		mXPUSHs( newSViv( maxlen ) );
		if ( easy->cb[CB_EASY_READ].data )
			mXPUSHs( newSVsv( easy->cb[CB_EASY_READ].data ) );

		PUTBACK;

		/*
		 * We set G_KEEPERR here, because multiple callbacks may be called in
		 * one run if we're using multi interface.
		 * However, it is set conditionally because we don't normally want to
		 * grab $@ generated by internal eval {} blocks
		 */
		perl_call_sv( easy->cb[CB_EASY_READ].func, G_SCALAR | G_EVAL
			| ( SvTRUE( ERRSV ) ? G_KEEPERR : 0 )  );

		SPAGAIN;

		if ( SvTRUE( ERRSV ) ) {
			/* cleanup after the error */
			(void) POPs;

			status = CURL_READFUNC_ABORT;
		} else {
			/* TODO: allow only scalar *refs* as output values */
			/* if value is not a ref, check for
			 * CURL_READFUNC_ABORT or CURL_READFUNC_PAUSE
			 */
			sv = POPs;
			data = SvPV( sv, len );

			/* only allowed to return the number of bytes asked for */
			len = len < maxlen ? len : maxlen;
			Copy( data, ptr, len, char );
			status = (size_t) ( len / size );
		}

		PUTBACK;
		FREETMPS;
		LEAVE;

		return status;
	} else {
		/* read input directly */
		PerlIO *f;
		if ( easy->cb[CB_EASY_READ].data ) { /* hope its a GLOB! */
			f = IoIFP( sv_2io( easy->cb[CB_EASY_READ].data ) );
		} else { /* punt to stdin */
			f = PerlIO_stdin();
		}
		return PerlIO_read( f, ptr, maxlen );
	}
} /*}}}*/

/* Progress callback for calling a perl callback */

static int
cb_easy_progress( void *userptr, double dltotal, double dlnow,
		double ultotal, double ulnow )
/*{{{*/ {
	dTHX;

	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;

	SV *args[] = {
		newSVsv( easy->perl_self ),
		newSVnv( dltotal ),
		newSVnv( dlnow ),
		newSVnv( ultotal ),
		newSVnv( ulnow ),
		NULL
	};
	int argn = 5;

	if ( easy->cb[CB_EASY_PROGRESS].data )
		args[ argn++ ] = newSVsv( easy->cb[CB_EASY_PROGRESS].data );

	return perl_curl_call( aTHX_ easy->cb[CB_EASY_PROGRESS].func, argn, args );
} /*}}}*/


#define EASY_DIE( ret )			\
	STMT_START {				\
		CURLcode code = (ret);	\
		if ( code != CURLE_OK )	\
			die_dual( code, curl_easy_strerror( code ) ); \
	} STMT_END


MODULE = WWW::CurlOO	PACKAGE = WWW::CurlOO::Easy	PREFIX = curl_easy_

INCLUDE: const-easy-xs.inc

PROTOTYPES: ENABLE

void
curl_easy_new( sclass="WWW::CurlOO::Easy", base=HASHREF_BY_DEFAULT )
	const char *sclass
	SV *base
	PREINIT:
		perl_curl_easy_t *easy;
		HV *stash;
	PPCODE:
		if ( ! SvOK( base ) || ! SvROK( base ) )
			croak( "object base must be a valid reference\n" );

		easy = perl_curl_easy_new();

		/* configure curl to always callback to the XS interface layer */
		curl_easy_setopt( easy->handle, CURLOPT_WRITEFUNCTION, cb_easy_write );
		curl_easy_setopt( easy->handle, CURLOPT_READFUNCTION, cb_easy_read );

		/* set our own object as the context for all curl callbacks */
		curl_easy_setopt( easy->handle, CURLOPT_FILE, easy );
		curl_easy_setopt( easy->handle, CURLOPT_INFILE, easy );

		/* we always collect this, in case it's wanted */
		curl_easy_setopt( easy->handle, CURLOPT_ERRORBUFFER, easy->errbuf );

		perl_curl_setptr( aTHX_ base, easy );
		stash = gv_stashpv( sclass, 0 );
		ST(0) = sv_bless( base, stash );

		XSRETURN(1);


void
curl_easy_duphandle( easy, base=HASHREF_BY_DEFAULT )
	WWW::CurlOO::Easy easy
	SV *base
	PREINIT:
		perl_curl_easy_t *clone;
		const char *sclass = "WWW::CurlOO::Easy";
		perl_curl_easy_callback_code_t i;
		HV *stash;
	PPCODE:
		/* {{{ */
		if ( ! SvOK( base ) || ! SvROK( base ) )
			croak( "object base must be a valid reference\n" );

		clone = perl_curl_easy_duphandle( easy );

		/* configure curl to always callback to the XS interface layer */

		curl_easy_setopt( clone->handle, CURLOPT_WRITEFUNCTION, cb_easy_write );
		curl_easy_setopt( clone->handle, CURLOPT_READFUNCTION, cb_easy_read );
		if ( easy->cb[ callback_index( CURLOPT_HEADERFUNCTION ) ].func
				|| easy->cb[ callback_index( CURLOPT_WRITEHEADER ) ].data ) {
			curl_easy_setopt( clone->handle, CURLOPT_HEADERFUNCTION, cb_easy_header );
			curl_easy_setopt( clone->handle, CURLOPT_WRITEHEADER, clone );
		}

		if ( easy->cb[ callback_index( CURLOPT_PROGRESSFUNCTION ) ].func
				|| easy->cb[ callback_index( CURLOPT_PROGRESSDATA ) ].data ) {
			curl_easy_setopt( clone->handle, CURLOPT_PROGRESSFUNCTION, cb_easy_progress );
			curl_easy_setopt( clone->handle, CURLOPT_PROGRESSDATA, clone );
		}

		if ( easy->cb[ callback_index( CURLOPT_DEBUGFUNCTION ) ].func
				|| easy->cb[ callback_index( CURLOPT_DEBUGDATA ) ].data ) {
			curl_easy_setopt( clone->handle, CURLOPT_DEBUGFUNCTION, cb_easy_debug );
			curl_easy_setopt( clone->handle, CURLOPT_DEBUGDATA, clone );
		}

		/* set our own object as the context for all curl callbacks */
		curl_easy_setopt( clone->handle, CURLOPT_FILE, clone );
		curl_easy_setopt( clone->handle, CURLOPT_INFILE, clone );
		curl_easy_setopt( clone->handle, CURLOPT_ERRORBUFFER, clone->errbuf );

		for( i = 0; i < CB_EASY_LAST; i++ ) {
			perl_curl_easy_register_callback( aTHX_ clone,
				&( clone->cb[i].func ), easy->cb[i].func );
			perl_curl_easy_register_callback( aTHX_ clone,
				&( clone->cb[i].data ), easy->cb[i].data );
		};

		/* clone strings and set */
		if ( easy->strings ) {
			optionll_t *in, **out;
			in = easy->strings;
			out = &clone->strings;
			do {
				Newx( *out, 1, optionll_t );
				(*out)->next = NULL;
				(*out)->option = in->option;
				(*out)->data = savepv( in->data );

				curl_easy_setopt( clone->handle, in->option, (*out)->data );
				out = &(*out)->next;
				in = in->next;
			} while ( in != NULL );
		}

		/* clone slists and set */
		if ( easy->slists ) {
			optionll_t *in, **out;
			struct curl_slist *sin, *sout;
			in = easy->slists;
			out = &clone->slists;
			do {
				Newx( *out, 1, optionll_t );
				sout = NULL;
				sin = in->data;
				do {
					sout = curl_slist_append( sout, sin->data );
				} while ( ( sin = sin->next ) != NULL );

				(*out)->next = NULL;
				(*out)->option = in->option;
				(*out)->data = sout;

				curl_easy_setopt( clone->handle, in->option, (*out)->data );
				out = &(*out)->next;
				in = in->next;
			} while ( in != NULL );
		}


		perl_curl_setptr( aTHX_ base, clone );
		stash = gv_stashpv( sclass, 0 );
		ST(0) = sv_bless( base, stash );

		XSRETURN(1);
		/* }}} */


void
curl_easy_setopt( easy, option, value )
	WWW::CurlOO::Easy easy
	int option
	SV *value
	PREINIT:
		CURLcode ret1 = CURLE_OK, ret2 = CURLE_OK;
	CODE:
		switch( option ) {
			/* SV * to user contexts for callbacks - any SV (glob,scalar,ref) */
			case CURLOPT_FILE:
			case CURLOPT_INFILE:
				perl_curl_easy_register_callback( aTHX_ easy,
					&( easy->cb[ callback_index( option ) ].data ), value );
				break;
			case CURLOPT_WRITEHEADER:
				ret1 = curl_easy_setopt( easy->handle, CURLOPT_HEADERFUNCTION,
					SvOK( value ) ? cb_easy_header : NULL );
				ret2 = curl_easy_setopt( easy->handle, option,
					SvOK( value ) ? easy : NULL );
				perl_curl_easy_register_callback( aTHX_ easy,
					&( easy->cb[ callback_index( option ) ].data ), value );
				break;
			case CURLOPT_PROGRESSDATA:
				ret1 = curl_easy_setopt( easy->handle, CURLOPT_PROGRESSFUNCTION,
					SvOK( value ) ? cb_easy_progress : NULL );
				ret2 = curl_easy_setopt( easy->handle, option,
					SvOK( value ) ? easy : NULL );
				perl_curl_easy_register_callback( aTHX_ easy,
					&( easy->cb[ callback_index( option ) ].data ), value );
				break;
			case CURLOPT_DEBUGDATA:
				ret1 = curl_easy_setopt( easy->handle, CURLOPT_DEBUGFUNCTION,
					SvOK( value ) ? cb_easy_debug : NULL );
				ret2 = curl_easy_setopt( easy->handle, option,
					SvOK( value ) ? easy : NULL );
				perl_curl_easy_register_callback( aTHX_ easy,
					&( easy->cb[ callback_index( option ) ].data ), value );
				break;

			/* SV * to a subroutine ref */
			case CURLOPT_WRITEFUNCTION:
			case CURLOPT_READFUNCTION:
				perl_curl_easy_register_callback( aTHX_ easy,
					&( easy->cb[ callback_index( option ) ].func ), value );
				break;
			case CURLOPT_HEADERFUNCTION:
				ret1 = curl_easy_setopt( easy->handle, option,
					SvOK( value ) ? cb_easy_header : NULL );
				ret2 = curl_easy_setopt( easy->handle, CURLOPT_WRITEHEADER,
					SvOK( value ) ? easy : NULL );
				perl_curl_easy_register_callback( aTHX_ easy,
					&( easy->cb[ callback_index( option ) ].func ), value );
				break;
			case CURLOPT_PROGRESSFUNCTION:
				ret1 = curl_easy_setopt( easy->handle, option,
					SvOK( value ) ? cb_easy_progress : NULL );
				ret2 = curl_easy_setopt( easy->handle, CURLOPT_PROGRESSDATA,
					SvOK( value ) ? easy : NULL );
				perl_curl_easy_register_callback( aTHX_ easy,
					&( easy->cb[ callback_index( option ) ].func ), value );
				break;
			case CURLOPT_DEBUGFUNCTION:
				ret1 = curl_easy_setopt( easy->handle, option,
					SvOK( value ) ? cb_easy_debug : NULL );
				ret2 = curl_easy_setopt( easy->handle, CURLOPT_DEBUGDATA,
					SvOK( value ) ? easy : NULL );
				perl_curl_easy_register_callback( aTHX_ easy,
					&( easy->cb[ callback_index( option ) ].func ), value );
				break;

			/* slist cases */
			case CURLOPT_HTTPHEADER:
			case CURLOPT_HTTP200ALIASES:
#ifdef CURLOPT_MAIL_RCPT
			case CURLOPT_MAIL_RCPT:
#endif
			case CURLOPT_QUOTE:
			case CURLOPT_POSTQUOTE:
			case CURLOPT_PREQUOTE:
#ifdef CURLOPT_RESOLVE
			case CURLOPT_RESOLVE:
#endif
			case CURLOPT_TELNETOPTIONS:
				ret1 = perl_curl_easy_setoptslist( aTHX_ easy, option, value, 1 );
				break;

			/* Pass in variable name for storing error messages. Yuck. */
			/* XXX: fix this */
			case CURLOPT_ERRORBUFFER:
			{
				STRLEN dummy;
				if ( easy->errbufvarname )
					free( easy->errbufvarname );
				easy->errbufvarname = strdup( (char *) SvPV( value, dummy ) );
			};
				break;

			/* tell curl to redirect STDERR - value should be a glob */
			case CURLOPT_STDERR:
				ret1 = curl_easy_setopt( easy->handle, option,
					PerlIO_findFILE( IoOFP( sv_2io( value ) ) ) );
				break;

			/* not working yet... */
			/* XXX: finish this */
			case CURLOPT_HTTPPOST:
				if ( sv_derived_from( value, "WWW::CurlOO::Form" ) ) {
					WWW__CurlOO__Form form;
					form = perl_curl_getptr( aTHX_ value );
					ret1 = curl_easy_setopt( easy->handle, option, form->post );
					if ( ret1 == CURLE_OK )
						easy->form_sv = newSVsv( value );
				} else
					croak( "value is not of type WWW::CurlOO::Form" );
				break;

			/* Curl share support from Anton Fedorov */
			/* XXX: and this */
			case CURLOPT_SHARE:
				if ( sv_derived_from( value, "WWW::CurlOO::Share" ) ) {
					WWW__CurlOO__Share share;
					share = perl_curl_getptr( aTHX_ value );
					ret1 = curl_easy_setopt( easy->handle, option, share->handle );
					if ( ret1 == CURLE_OK )
						easy->share_sv = newSVsv( value );
				} else
					croak( "value is not of type WWW::CurlOO::Share" );
				break;

			case CURLOPT_PRIVATE:
				croak( "CURLOPT_PRIVATE is off limits" );
				break;

			/* default cases */
			default:
				if ( option < CURLOPTTYPE_OBJECTPOINT ) {
					/* A long (integer) value */
					ret1 = curl_easy_setopt( easy->handle, option, (long) SvIV( value ) );
				}
				else if ( option < CURLOPTTYPE_FUNCTIONPOINT ) {
					/* An objectpoint - string */
					char *pv;
					if ( SvOK( value ) ) {
						char **ppv;
						ppv = perl_curl_optionll_add( aTHX_ &easy->strings, option );
						if ( ppv )
							Safefree( *ppv );
						pv = *ppv = savesvpv( value );
					} else {
						pv = perl_curl_optionll_del( aTHX_ &easy->strings, option );
						if ( pv )
							Safefree( pv );
						pv = NULL;
					}
					ret1 = curl_easy_setopt( easy->handle, option, pv );
				}
				else if ( option < CURLOPTTYPE_OFF_T ) { /* A function - notreached? */
					croak( "Unknown curl option of type function" );
				}
				else { /* A LARGE file option using curl_off_t, handling larger than 32bit sizes without 64bit integer support */
					if ( SvOK( value ) && looks_like_number( value ) ) {
						STRLEN dummy = 0;
						char* pv = SvPV( value, dummy );
						char* pdummy;
						ret1 = curl_easy_setopt( easy->handle, option,
							(curl_off_t) strtoll( pv, &pdummy, 10 ) );
					}
				};
				break;
		};
		EASY_DIE( ret1 ? ret1 : ret2 );


void
curl_easy_pushopt( easy, option, value )
	WWW::CurlOO::Easy easy
	int option
	SV *value
	PREINIT:
		CURLcode ret;
	CODE:
		ret = perl_curl_easy_setoptslist( aTHX_ easy, option, value, 0 );
		EASY_DIE( ret );


void
curl_easy_perform( easy )
	WWW::CurlOO::Easy easy
	PREINIT:
		CURLcode ret;
	CODE:
		perl_curl_easy_update( easy, sv_2mortal( newSVsv( ST(0) ) ) );
		CLEAR_ERRSV();
		ret = curl_easy_perform( easy->handle );

		/* rethrow errors */
		if ( SvTRUE( ERRSV ) )
			croak( NULL );

		EASY_DIE( ret );


SV *
curl_easy_getinfo( easy, option )
	WWW::CurlOO::Easy easy
	int option
	PREINIT:
		CURLcode ret = CURLE_OK;
	CODE:
		/* {{{ */
		switch( option & CURLINFO_TYPEMASK ) {
			case CURLINFO_STRING:
			{
				char * vchar;
				ret = curl_easy_getinfo( easy->handle, option, &vchar );
				RETVAL = newSVpv( vchar, 0 );
				break;
			}
			case CURLINFO_LONG:
			{
				long vlong;
				ret = curl_easy_getinfo( easy->handle, option, &vlong );
				RETVAL = newSViv( vlong );
				break;
			}
			case CURLINFO_DOUBLE:
			{
				double vdouble;
				ret = curl_easy_getinfo( easy->handle, option, &vdouble );
				RETVAL = newSVnv( vdouble );
				break;
			}
			case CURLINFO_SLIST:
			{
				struct curl_slist *vlist, *entry;
				AV *items = newAV();
				ret = curl_easy_getinfo( easy->handle, option, &vlist );
				if ( vlist != NULL ) {
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
		if ( ret != CURLE_OK ) {
			sv_2mortal( RETVAL );
			EASY_DIE( ret );
		}
		/* }}} */
	OUTPUT:
		RETVAL

char *
curl_easy_errbuf( easy )
	WWW::CurlOO::Easy easy
	CODE:
		RETVAL = easy->errbuf;
	OUTPUT:
		RETVAL

size_t
curl_easy_send( easy, buffer )
	WWW::CurlOO::Easy easy
	SV *buffer
	CODE:
		/* {{{ */
#if LIBCURL_VERSION_NUM >= 0x071202
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
#else
		croak( "curl_easy_send() not available in curl before 7.18.2\n" );
		RETVAL = 0;
#endif
		/* }}} */
	OUTPUT:
		RETVAL


void
curl_easy_recv( easy, buffer, length )
	WWW::CurlOO::Easy easy
	SV *buffer
	size_t length
	CODE:
#if LIBCURL_VERSION_NUM >= 0x071202
		CURLcode ret;
		size_t out_len;
		char *tmpbuf;

		Newx( tmpbuf, length, char );
		ret = curl_easy_recv( easy->handle, tmpbuf, length, &out_len );
		EASY_DIE( ret );

		sv_setpvn( buffer, tmpbuf, out_len );

		Safefree( tmpbuf );
#else
		croak( "curl_easy_recv() not available in curl before 7.18.2\n" );
#endif


void
curl_easy_DESTROY( easy )
	WWW::CurlOO::Easy easy
	CODE:
		perl_curl_easy_delete( aTHX_ easy );


SV *
curl_easy_strerror( ... )
	PROTOTYPE: $;$
	PREINIT:
		const char *errstr;
	CODE:
		if ( items < 1 || items > 2 )
			croak_xs_usage(cv,  "[easy], errnum");
		errstr = curl_easy_strerror( SvIV( ST( items - 1 ) ) );
		RETVAL = newSVpv( errstr, 0 );
	OUTPUT:
		RETVAL
