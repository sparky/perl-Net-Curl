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
		perl_curl_easy_t *easy, callback_t *cb )
/*{{{*/ {
	dTHX;
	if ( cb->func ) { /* We are doing a callback to perl */
		SV *args[] = {
			newSVsv( easy->perl_self ),
			ptr
				? newSVpvn( (char *) ptr, (STRLEN) (size * nmemb) )
				: newSVsv( &PL_sv_undef )
		};

		return PERL_CURL_CALL( cb, args );
	} else {
		return write_to_ctx( aTHX_ cb->data, ptr, size * nmemb );
	}
} /*}}}*/

/* debug fwrite callback */
static size_t
fwrite_wrapper2( const void *ptr, size_t size, perl_curl_easy_t *easy,
		callback_t *cb, curl_infotype type )
/*{{{*/ {
	dTHX;

	if ( cb->func ) { /* We are doing a callback to perl */
		SV *args[] = {
			newSVsv( easy->perl_self ),
			newSViv( type ),
			ptr
				? newSVpvn( (char *) ptr, (STRLEN) (size) )
				: newSVsv( &PL_sv_undef )
		};

		return PERL_CURL_CALL( cb, args );
	} else {
		return write_to_ctx( aTHX_ cb->data, ptr, size );
	}
} /*}}}*/

/* Write callback for calling a perl callback */
static size_t
cb_easy_write( const void *ptr, size_t size, size_t nmemb, void *userptr )
/*{{{*/ {
	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	return fwrite_wrapper( ptr, size, nmemb, easy,
			&easy->cb[ CB_EASY_WRITE ] );
} /*}}}*/

/* header callback for calling a perl callback */
static size_t
cb_easy_header( const void *ptr, size_t size, size_t nmemb,
		void *userptr )
/*{{{*/ {
	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;

	return fwrite_wrapper( ptr, size, nmemb, easy,
			&easy->cb[ CB_EASY_HEADER ] );
} /*}}}*/

/* debug callback for calling a perl callback */
static int
cb_easy_debug( CURL* handle, curl_infotype type, char *ptr, size_t size,
		void *userptr )
/*{{{*/ {
	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;

	return fwrite_wrapper2( ptr, size, easy,
			&easy->cb[ CB_EASY_DEBUG ], type );
} /*}}}*/

/* read callback for calling a perl callback */
static size_t
cb_easy_read( void *ptr, size_t size, size_t nmemb, void *userptr )
/*{{{*/ {
	dTHX;
	dSP;

	size_t maxlen;
	perl_curl_easy_t *easy;
	callback_t *cb;

	easy = (perl_curl_easy_t *) userptr;

	maxlen = size * nmemb;
	cb = &easy->cb[ CB_EASY_READ ];

	if ( cb->func ) {
		SV *sv;
		size_t status = CURL_READFUNC_ABORT;
		SV *olderrsv = NULL;

		ENTER;
		SAVETMPS;

		PUSHMARK( SP );

		/* $easy, $maxsize, $userdata */
		EXTEND( SP, 2 );
		mPUSHs( newSVsv( easy->perl_self ) );
		mPUSHs( newSViv( maxlen ) );
		if ( cb->data )
			mXPUSHs( newSVsv( cb->data ) );

		PUTBACK;

		if ( SvTRUE( ERRSV ) )
			olderrsv = sv_2mortal( newSVsv( ERRSV ) );

		perl_call_sv( cb->func, G_SCALAR | G_EVAL );

		SPAGAIN;

		/* get returned value, will be undef on error (ERRSV set) */
		sv = POPs;

		if ( ! SvOK( sv ) ) {
			status = CURL_READFUNC_ABORT;
		} else if ( SvROK( sv ) ) {
			SV *datasv;
			char *data;
			STRLEN len;
			datasv = SvRV( sv );
			data = SvPV( datasv, len );

			if ( len > maxlen )
				len = maxlen;

			Copy( data, ptr, len, char );

			/* CITE: Your function must return the actual number of bytes
			 * that you stored in that memory area. */
			status = (size_t) len;

		} else if ( SvIOK( sv ) ) {
			IV val = SvIV( sv );
			if ( val == 0 /* end of file */
					|| val == CURL_READFUNC_ABORT
#ifdef CURL_READFUNC_PAUSE
					|| val == CURL_READFUNC_PAUSE
#endif
				)
				status = val;
			else
				sv_setpvf( ERRSV, "invalid numeric return value in read "
					"callback: %"IVdf, val );
		} else {
			sv_setpvf( ERRSV, "invalid return value in read callback" );
		}

		if ( olderrsv )
			sv_setsv( ERRSV, olderrsv );

		PUTBACK;
		FREETMPS;
		LEAVE;

		return status;
	} else {
		/* read input directly */
		PerlIO *f;
		if ( cb->data ) { /* hope its a GLOB! */
			f = IoIFP( sv_2io( cb->data ) );
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
	callback_t *cb = &easy->cb[ CB_EASY_PROGRESS ];

	SV *args[] = {
		newSVsv( easy->perl_self ),
		newSVnv( dltotal ),
		newSVnv( dlnow ),
		newSVnv( ultotal ),
		newSVnv( ulnow )
	};

	return PERL_CURL_CALL( cb, args );
} /*}}}*/

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

		perl_curl_setptr( aTHX_ base, easy );
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

		/* XXX: copy share and form */

		perl_curl_setptr( aTHX_ base, clone );
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
		CURLcode ret1 = CURLE_OK, ret2 = CURLE_OK;
	CODE:
		switch( option ) {
			/* SV * to user contexts for callbacks - any SV (glob,scalar,ref) */
			case CURLOPT_FILE:
			case CURLOPT_INFILE:
				SvREPLACE( easy->cb[ callback_index( option ) ].data, value );
				break;
			case CURLOPT_WRITEHEADER:
				ret1 = curl_easy_setopt( easy->handle, CURLOPT_HEADERFUNCTION,
					SvOK( value ) ? cb_easy_header : NULL );
				ret2 = curl_easy_setopt( easy->handle, option,
					SvOK( value ) ? easy : NULL );
				SvREPLACE( easy->cb[ callback_index( option ) ].data, value );
				break;
			case CURLOPT_PROGRESSDATA:
				ret1 = curl_easy_setopt( easy->handle, CURLOPT_PROGRESSFUNCTION,
					SvOK( value ) ? cb_easy_progress : NULL );
				ret2 = curl_easy_setopt( easy->handle, option,
					SvOK( value ) ? easy : NULL );
				SvREPLACE( easy->cb[ callback_index( option ) ].data, value );
				break;
			case CURLOPT_DEBUGDATA:
				ret1 = curl_easy_setopt( easy->handle, CURLOPT_DEBUGFUNCTION,
					SvOK( value ) ? cb_easy_debug : NULL );
				ret2 = curl_easy_setopt( easy->handle, option,
					SvOK( value ) ? easy : NULL );
				SvREPLACE( easy->cb[ callback_index( option ) ].data, value );
				break;

			/* SV * to a subroutine ref */
			case CURLOPT_WRITEFUNCTION:
			case CURLOPT_READFUNCTION:
				SvREPLACE( easy->cb[ callback_index( option ) ].func, value );
				break;
			case CURLOPT_HEADERFUNCTION:
				ret1 = curl_easy_setopt( easy->handle, option,
					SvOK( value ) ? cb_easy_header : NULL );
				ret2 = curl_easy_setopt( easy->handle, CURLOPT_WRITEHEADER,
					SvOK( value ) ? easy : NULL );
				SvREPLACE( easy->cb[ callback_index( option ) ].func, value );
				break;
			case CURLOPT_PROGRESSFUNCTION:
				ret1 = curl_easy_setopt( easy->handle, option,
					SvOK( value ) ? cb_easy_progress : NULL );
				ret2 = curl_easy_setopt( easy->handle, CURLOPT_PROGRESSDATA,
					SvOK( value ) ? easy : NULL );
				SvREPLACE( easy->cb[ callback_index( option ) ].func, value );
				break;
			case CURLOPT_DEBUGFUNCTION:
				ret1 = curl_easy_setopt( easy->handle, option,
					SvOK( value ) ? cb_easy_debug : NULL );
				ret2 = curl_easy_setopt( easy->handle, CURLOPT_DEBUGDATA,
					SvOK( value ) ? easy : NULL );
				SvREPLACE( easy->cb[ callback_index( option ) ].func, value );
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

			/* XXX: fix this */
			case CURLOPT_ERRORBUFFER:
				croak( "CURLOPT_ERRORBUFFER is not supported, use $easy->error instead" );
				break;

			/* tell curl to redirect STDERR - value should be a glob */
			case CURLOPT_STDERR:
				ret1 = curl_easy_setopt( easy->handle, option,
					PerlIO_findFILE( IoOFP( sv_2io( value ) ) ) );
				break;

			/* not working yet... */
			/* XXX: finish this */
			case CURLOPT_HTTPPOST:
				if ( easy->form_sv ) {
					ret2 = curl_easy_setopt( easy->handle, option, NULL );
					sv_2mortal( easy->form_sv );
					easy->form_sv = NULL;
				}

				if ( SvOK( value ) ) {
					WWW__CurlOO__Form form;
					form = perl_curl_getptr_fatal( aTHX_ value,
						"CURLOPT_HTTPPOST", "WWW::CurlOO::Form" );

					easy->form_sv = newSVsv( value );
					ret1 = curl_easy_setopt( easy->handle, option, form->post );
				}
				break;

			case CURLOPT_SHARE:
				if ( easy->share_sv ) {
					ret2 = curl_easy_setopt( easy->handle, option, NULL );
					sv_2mortal( easy->share_sv );
					easy->share_sv = NULL;
				}

				if ( SvOK( value ) ) {
					WWW__CurlOO__Share share;
					share = perl_curl_getptr_fatal( aTHX_ value,
						"CURLOPT_SHARE", "WWW::CurlOO::Share" );

					/* copy sv before setopt because this may trigger a callback */
					easy->share_sv = newSVsv( value );
					ret1 = curl_easy_setopt( easy->handle, option, share->handle );
				}
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
						ppv = perl_curl_simplell_add( aTHX_ &easy->strings, option );
						if ( ppv )
							Safefree( *ppv );
#ifdef savesvpv
						pv = *ppv = savesvpv( value );
#else
						{
							STRLEN len;
							char *src = SvPV( value, len );
							pv = *ppv = savepvn( src, len );
						}
#endif
					} else {
						pv = perl_curl_simplell_del( aTHX_ &easy->strings, option );
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
	PREINIT:
		CURLcode ret = CURLE_OK;
	CODE:
		/* XXX: die right away */
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
	OUTPUT:
		RETVAL

char *
error( easy )
	WWW::CurlOO::Easy easy
	CODE:
		RETVAL = easy->errbuf;
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


void
DESTROY( easy )
	WWW::CurlOO::Easy easy
	CODE:
		perl_curl_easy_delete( aTHX_ easy );


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


=head1 Extensions

Functions that do not have libcurl equivalents.

=cut


void
pushopt( easy, option, value )
	WWW::CurlOO::Easy easy
	int option
	SV *value
	PREINIT:
		CURLcode ret;
	CODE:
		ret = perl_curl_easy_setoptslist( aTHX_ easy, option, value, 0 );
		EASY_DIE( ret );


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
