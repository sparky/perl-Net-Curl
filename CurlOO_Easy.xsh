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

struct perl_curl_easy_s {
	/* last seen version of this object */
	SV *perl_self;

	/* The main curl handle */
	CURL *curl;

	/* Lists that can be set via curl_easy_setopt() */
	I32 *y;
	struct curl_slist *slist[ SLIST_LAST ];

	/* list of callbacks */
	callback_t cb[ CB_EASY_LAST ];

	/* copy of error buffer var for caller*/
	char errbuf[CURL_ERROR_SIZE+1];
	char *errbufvarname;

	stringll_t *strings;

	/* parent, if easy is attached to any multi object */
	perl_curl_multi_t *multi;

	/* if easy is attached to any share object */
	perl_curl_share_t *share;
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
	croak("Bad callback index requested\n");
	return CB_EASY_LAST;
} /*}}}*/


static int
perl_curl_easy_setoptslist( pTHX_ perl_curl_easy_t *self, CURLoption option, SV *value,
		int clear )
/*{{{*/ {
	perl_curl_easy_slist_code_t si = 0;
	AV *array;
	int array_len;
	struct curl_slist *slist = NULL;
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
	slist = self->slist[ si ];

	if ( slist && clear ) {
		curl_slist_free_all( slist );
		slist = NULL;
	}

	/* copy perl values into this slist */
	self->slist[ si ] = slist = perl_curl_array2slist( aTHX_ slist, value );

	/* pass the list into curl_easy_setopt() */
	return curl_easy_setopt(self->curl, option, slist);
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

	for ( i = 0; i < CB_EASY_LAST; i++ ) {
		sv_2mortal( self->cb[i].func );
		sv_2mortal( self->cb[i].data );
	}

	if ( self->errbufvarname )
		free( self->errbufvarname );

	perl_curl_stringll_free( aTHX_ self->strings );

	Safefree( self );

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
			self->cb[CB_EASY_WRITE].func, self->cb[CB_EASY_WRITE].data );
} /*}}}*/

/* header callback for calling a perl callback */
static size_t
cb_easy_header( const void *ptr, size_t size, size_t nmemb,
		void *userptr )
/*{{{*/ {
	perl_curl_easy_t *self;
	self=(perl_curl_easy_t *)userptr;

	return fwrite_wrapper( ptr, size, nmemb, self,
			self->cb[CB_EASY_HEADER].func, self->cb[CB_EASY_HEADER].data );
} /*}}}*/

/* debug callback for calling a perl callback */
static int
cb_easy_debug( CURL* handle, curl_infotype type, char *ptr, size_t size,
		void *userptr )
/*{{{*/ {
	perl_curl_easy_t *self;
	self=(perl_curl_easy_t *)userptr;

	return fwrite_wrapper2( ptr, size, self,
			self->cb[CB_EASY_DEBUG].func, self->cb[CB_EASY_DEBUG].data, type);
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

	if (self->cb[CB_EASY_READ].func) { /* We are doing a callback to perl */
		char *data;
		int count;
		SV *sv;
		STRLEN len;

		ENTER ;
		SAVETMPS ;

		PUSHMARK(SP) ;

		if (self->cb[CB_EASY_READ].data) {
			sv = self->cb[CB_EASY_READ].data;
		} else {
			sv = &PL_sv_undef;
		}

		/* $easy, $maxsize, $userdata */
		XPUSHs( sv_2mortal( newSVsv( self->perl_self ) ) );
		XPUSHs( sv_2mortal( newSViv( maxlen ) ) );
		XPUSHs( sv_2mortal( newSVsv( sv ) ) );

		PUTBACK ;
		count = perl_call_sv( self->cb[CB_EASY_READ].func, G_SCALAR );
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
		if (self->cb[CB_EASY_READ].data) { /* hope its a GLOB! */
			f = IoIFP(sv_2io(self->cb[CB_EASY_READ].data));
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
	if ( self->cb[CB_EASY_PROGRESS].data ) {
		XPUSHs( sv_2mortal( newSVsv( self->cb[CB_EASY_PROGRESS].data ) ) );
	} else {
		XPUSHs( &PL_sv_undef );
	}

	PUTBACK;
	count = perl_call_sv(self->cb[CB_EASY_PROGRESS].func, G_SCALAR);
	SPAGAIN;

	if (count != 1)
		croak("callback for CURLOPT_PROGRESSFUNCTION didn't return 1\n");

	count = POPi;

	PUTBACK;
	FREETMPS;
	LEAVE;
	return count;
} /*}}}*/



/* XS_SECTION */
#ifdef XS_SECTION

MODULE = WWW::CurlOO	PACKAGE = WWW::CurlOO::Easy	PREFIX = curl_easy_

INCLUDE: const-easy-xs.inc

PROTOTYPES: ENABLE

void
curl_easy_new( sclass="WWW::CurlOO::Easy", base=HASHREF_BY_DEFAULT )
	const char *sclass
	SV *base
	PREINIT:
		perl_curl_easy_t *self;
		HV *stash;
	PPCODE:
		if ( ! SvOK( base ) || ! SvROK( base ) )
			croak( "object base must be a valid reference\n" );

		self = perl_curl_easy_new();

		Newxz( self->y, 1, I32 );
		if ( !self->y )
			croak ("out of memory");
		(*self->y)++;

		/* configure curl to always callback to the XS interface layer */
		curl_easy_setopt( self->curl, CURLOPT_WRITEFUNCTION, cb_easy_write );
		curl_easy_setopt( self->curl, CURLOPT_READFUNCTION, cb_easy_read );

		/* set our own object as the context for all curl callbacks */
		curl_easy_setopt( self->curl, CURLOPT_FILE, self );
		curl_easy_setopt( self->curl, CURLOPT_INFILE, self );

		/* we always collect this, in case it's wanted */
		curl_easy_setopt( self->curl, CURLOPT_ERRORBUFFER, self->errbuf );

		perl_curl_setptr( aTHX_ base, self );
		stash = gv_stashpv( sclass, 0 );
		ST(0) = sv_bless( base, stash );

		XSRETURN(1);


void
curl_easy_duphandle( self, base=HASHREF_BY_DEFAULT )
	WWW::CurlOO::Easy self
	SV *base
	PREINIT:
		perl_curl_easy_t *clone;
		char *sclass = "WWW::CurlOO::Easy";
		perl_curl_easy_callback_code_t i;
		HV *stash;
	PPCODE:
		/* {{{ */
		if ( ! SvOK( base ) || ! SvROK( base ) )
			croak( "object base must be a valid reference\n" );

		clone=perl_curl_easy_duphandle(self);
		clone->y = self->y;
		(*self->y)++;

		/* configure curl to always callback to the XS interface layer */

		curl_easy_setopt(clone->curl, CURLOPT_WRITEFUNCTION, cb_easy_write);
		curl_easy_setopt(clone->curl, CURLOPT_READFUNCTION, cb_easy_read);
		if (self->cb[callback_index(CURLOPT_HEADERFUNCTION)].func || self->cb[callback_index(CURLOPT_WRITEHEADER)].data) {
			curl_easy_setopt(clone->curl, CURLOPT_HEADERFUNCTION, cb_easy_header);
			curl_easy_setopt(clone->curl, CURLOPT_WRITEHEADER, clone);
		}

		if (self->cb[callback_index(CURLOPT_PROGRESSFUNCTION)].func || self->cb[callback_index(CURLOPT_PROGRESSDATA)].data) {
			curl_easy_setopt(clone->curl, CURLOPT_PROGRESSFUNCTION, cb_easy_progress);
			curl_easy_setopt(clone->curl, CURLOPT_PROGRESSDATA, clone);
		}

		if (self->cb[callback_index(CURLOPT_DEBUGFUNCTION)].func || self->cb[callback_index(CURLOPT_DEBUGDATA)].data) {
			curl_easy_setopt(clone->curl, CURLOPT_DEBUGFUNCTION, cb_easy_debug);
			curl_easy_setopt(clone->curl, CURLOPT_DEBUGDATA, clone);
		}

		/* set our own object as the context for all curl callbacks */
		curl_easy_setopt(clone->curl, CURLOPT_FILE, clone);
		curl_easy_setopt(clone->curl, CURLOPT_INFILE, clone);
		curl_easy_setopt(clone->curl, CURLOPT_ERRORBUFFER, clone->errbuf);

		for(i=0;i<CB_EASY_LAST;i++) {
			perl_curl_easy_register_callback( aTHX_ clone,&(clone->cb[i].func), self->cb[i].func);
			perl_curl_easy_register_callback( aTHX_ clone,&(clone->cb[i].data), self->cb[i].data);
		};

		/* clone strings and set */
		{
			stringll_t *in, **out;
			in = self->strings;
			out = &clone->strings;
			while ( in ) {
				Newx( *out, 1, stringll_t );
				(*out)->next = NULL;
				(*out)->option = in->option;
				(*out)->string = savepv( in->string );

				curl_easy_setopt( clone->curl, in->option, (*out)->string );
				out = &(*out)->next;
				in = in->next;
			}
		}

		perl_curl_setptr( aTHX_ base, clone );
		stash = gv_stashpv( sclass, 0 );
		ST(0) = sv_bless( base, stash );

		XSRETURN(1);
		/* }}} */


int
curl_easy_setopt( self, option, value )
	WWW::CurlOO::Easy self
	int option
	SV *value
	CODE:
		/* {{{ */
		RETVAL=CURLE_OK;
		switch( option ) {
			/* SV * to user contexts for callbacks - any SV (glob,scalar,ref) */
			case CURLOPT_FILE:
			case CURLOPT_INFILE:
				perl_curl_easy_register_callback( aTHX_ self,
						&(self->cb[callback_index(option)].data), value);
				break;
			case CURLOPT_WRITEHEADER:
				curl_easy_setopt(self->curl, CURLOPT_HEADERFUNCTION, SvOK(value) ? cb_easy_header : NULL);
				curl_easy_setopt(self->curl, option, SvOK(value) ? self : NULL);
				perl_curl_easy_register_callback( aTHX_ self,&(self->cb[callback_index(option)].data),value);
				break;
			case CURLOPT_PROGRESSDATA:
				curl_easy_setopt(self->curl, CURLOPT_PROGRESSFUNCTION, SvOK(value) ? cb_easy_progress : NULL);
				curl_easy_setopt(self->curl, option, SvOK(value) ? self : NULL);
				perl_curl_easy_register_callback( aTHX_ self,&(self->cb[callback_index(option)].data), value);
				break;
			case CURLOPT_DEBUGDATA:
				curl_easy_setopt(self->curl, CURLOPT_DEBUGFUNCTION, SvOK(value) ? cb_easy_debug : NULL);
				curl_easy_setopt(self->curl, option, SvOK(value) ? self : NULL);
				perl_curl_easy_register_callback( aTHX_ self,&(self->cb[callback_index(option)].data), value);
				break;

			/* SV * to a subroutine ref */
			case CURLOPT_WRITEFUNCTION:
			case CURLOPT_READFUNCTION:
				perl_curl_easy_register_callback( aTHX_ self,&(self->cb[callback_index(option)].func), value);
				break;
			case CURLOPT_HEADERFUNCTION:
				curl_easy_setopt(self->curl, option, SvOK(value) ? cb_easy_header : NULL);
				curl_easy_setopt(self->curl, CURLOPT_WRITEHEADER, SvOK(value) ? self : NULL);
				perl_curl_easy_register_callback( aTHX_ self,&(self->cb[callback_index(option)].func), value);
				break;
			case CURLOPT_PROGRESSFUNCTION:
				curl_easy_setopt(self->curl, option, SvOK(value) ? cb_easy_progress : NULL);
				curl_easy_setopt(self->curl, CURLOPT_PROGRESSDATA, SvOK(value) ? self : NULL);
				perl_curl_easy_register_callback( aTHX_ self,&(self->cb[callback_index(option)].func), value);
				break;
			case CURLOPT_DEBUGFUNCTION:
				curl_easy_setopt(self->curl, option, SvOK(value) ? cb_easy_debug : NULL);
				curl_easy_setopt(self->curl, CURLOPT_DEBUGDATA, SvOK(value) ? self : NULL);
				perl_curl_easy_register_callback( aTHX_ self,&(self->cb[callback_index(option)].func), value);
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
				RETVAL = perl_curl_easy_setoptslist( aTHX_ self, option, value, 1 );
				if ( RETVAL == -1 )
					croak( "Specified option does not accept slists" );
				break;

			/* Pass in variable name for storing error messages. Yuck. */
			/* XXX: fix this */
			case CURLOPT_ERRORBUFFER:
			{
				STRLEN dummy;
				if (self->errbufvarname)
					free(self->errbufvarname);
				self->errbufvarname = strdup((char *)SvPV(value, dummy));
			};
				break;

			/* tell curl to redirect STDERR - value should be a glob */
			case CURLOPT_STDERR:
				RETVAL = curl_easy_setopt(self->curl, option, PerlIO_findFILE( IoOFP(sv_2io(value)) ) );
				break;

			/* not working yet... */
			case CURLOPT_HTTPPOST:
				if (sv_derived_from(value, "WWW::CurlOO::Form")) {
					WWW__CurlOO__Form wrapper;
					wrapper = perl_curl_getptr( aTHX_ value );
					RETVAL = curl_easy_setopt(self->curl, option, wrapper->post);
				} else
					croak("value is not of type WWW::CurlOO::Form");
				break;

			/* Curl share support from Anton Fedorov */
			case CURLOPT_SHARE:
				if (sv_derived_from(value, "WWW::CurlOO::Share")) {
					WWW__CurlOO__Share wrapper;
					wrapper = perl_curl_getptr( aTHX_ value );
					RETVAL = curl_easy_setopt(self->curl, option, wrapper->curlsh);
					if ( RETVAL == CURLE_OK )
						self->share = wrapper;
				} else
					croak("value is not of type WWW::CurlOO::Share");
				break;

			case CURLOPT_PRIVATE:
				croak( "CURLOPT_PRIVATE is off limits" );
				break;

			/* default cases */
			default:
				if (option < CURLOPTTYPE_OBJECTPOINT) {
					/* A long (integer) value */
					RETVAL = curl_easy_setopt(self->curl, option, (long)SvIV(value));
				}
				else if (option < CURLOPTTYPE_FUNCTIONPOINT) {
					/* An objectpoint - string */
					char *pv = perl_curl_stringll_set( aTHX_ &self->strings,
						option, value );
					RETVAL = curl_easy_setopt( self->curl, option, pv );
				}
				else if (option < CURLOPTTYPE_OFF_T) { /* A function - notreached? */
					croak("Unknown curl option of type function");
				}
				else { /* A LARGE file option using curl_off_t, handling larger than 32bit sizes without 64bit integer support */
					if (SvOK(value) && looks_like_number(value)) {
						STRLEN dummy = 0;
						char* pv = SvPV(value, dummy);
						char* pdummy;
						RETVAL = curl_easy_setopt(self->curl, option, (curl_off_t) strtoll(pv,&pdummy,10));
					} else {
						RETVAL = 0;
					}
				};
				break;
		};
		/* }}} */
	OUTPUT:
		RETVAL


int
curl_easy_pushopt(self, option, value)
	WWW::CurlOO::Easy self
	int option
	SV *value
	CODE:
		RETVAL = perl_curl_easy_setoptslist( aTHX_ self, option, value, 0 );
		if ( RETVAL == -1 )
			croak( "Specified option does not accept slists" );
	OUTPUT:
		RETVAL


int
curl_easy_perform(self)
	WWW::CurlOO::Easy self
	CODE:
		/* {{{ */
		perl_curl_easy_update( self, ST(0) );
		/* perform the actual curl fetch */
		RETVAL = curl_easy_perform(self->curl);

		if (RETVAL && self->errbufvarname) {
			/* If an error occurred and a varname for error messages has been
			specified, store the error message. */
			SV *sv = perl_get_sv(self->errbufvarname, TRUE | GV_ADDMULTI);
			sv_setpv(sv, self->errbuf);
		}
		/* }}} */
	OUTPUT:
		RETVAL


SV *
curl_easy_getinfo( self, option )
	WWW::CurlOO::Easy self
	int option
	CODE:
		/* {{{ */
		switch( option & CURLINFO_TYPEMASK ) {
			case CURLINFO_STRING:
			{
				char * vchar;
				curl_easy_getinfo(self->curl, option, &vchar);
				RETVAL = newSVpv(vchar,0);
				break;
			}
			case CURLINFO_LONG:
			{
				long vlong;
				curl_easy_getinfo(self->curl, option, &vlong);
				RETVAL = newSViv(vlong);
				break;
			}
			case CURLINFO_DOUBLE:
			{
				double vdouble;
				curl_easy_getinfo(self->curl, option, &vdouble);
				RETVAL = newSVnv(vdouble);
				break;
			}
			case CURLINFO_SLIST:
			{
				struct curl_slist *vlist, *entry;
				AV *items = newAV();
				curl_easy_getinfo(self->curl, option, &vlist);
				if (vlist != NULL) {
					entry = vlist;
					while (entry) {
						av_push(items, newSVpv(entry->data, 0));
						entry = entry->next;
					}
					curl_slist_free_all(vlist);
				}
				RETVAL = newRV(sv_2mortal((SV *) items));
				break;
			}
			default: {
				croak( "invalid getinfo option" );
				break;
			}
		}
		/* }}} */
	OUTPUT:
		RETVAL

char *
curl_easy_errbuf(self)
	WWW::CurlOO::Easy self
	CODE:
		RETVAL = self->errbuf;
	OUTPUT:
		RETVAL

size_t
curl_easy_send( self, buffer )
	WWW::CurlOO::Easy self
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
		ret = curl_easy_send( self->curl, pv, len, &out_len );
		if ( ret != CURLE_OK )
			croak( "curl_easy_send() didn't return CURLE_OK\n" );

		RETVAL = out_len;
#else
		croak( "curl_easy_send() not available in curl before 7.18.2\n" );
		RETVAL = 0;
#endif
		/* }}} */
	OUTPUT:
		RETVAL

int
curl_easy_recv( self, buffer, length )
	WWW::CurlOO::Easy self
	SV *buffer
	size_t length
	CODE:
		/* {{{ */
#if LIBCURL_VERSION_NUM >= 0x071202
		CURLcode ret;
		size_t out_len;
		char *tmpbuf;

		Newx( tmpbuf, length, char);
		ret = curl_easy_recv( self->curl, tmpbuf, length, &out_len );
		if ( ret != CURLE_OK )
			sv_setsv( buffer, &PL_sv_undef );
		else
			sv_setpvn( buffer, tmpbuf, out_len );

		Safefree( tmpbuf );
		RETVAL = ret;
#else
		croak( "curl_easy_recv() not available in curl before 7.18.2\n" );
		RETVAL = 0;
#endif
		/* }}} */
	OUTPUT:
		RETVAL


void
curl_easy_DESTROY(self)
	WWW::CurlOO::Easy self
	CODE:
		perl_curl_easy_delete( aTHX_ self );


SV *
curl_easy_strerror(self, errornum)
	WWW::CurlOO::Easy self
	int errornum
	PREINIT:
		const char *errstr;
		(void) self; /* unused */
	CODE:
		errstr = curl_easy_strerror( errornum );
		RETVAL = newSVpv( errstr, 0 );
	OUTPUT:
		RETVAL

#endif
