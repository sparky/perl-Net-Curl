/* vim: ts=4:sw=4:ft=xs:fdm=marker: */
/*
 * Copyright 2011 (C) Przemyslaw Iskra <sparky at pld-linux.org>
 *
 * Loosely based on code by Cris Bailiff <c.bailiff+curl at devsecure.com>,
 * and subsequent fixes by other contributors.
 */


typedef enum {
	CB_SHARE_LOCK = 0,
	CB_SHARE_UNLOCK,
	CB_SHARE_LAST,
} perl_curl_share_callback_code_t;

struct perl_curl_share_s {
	/* last seen version of this object */
	SV *perl_self;

	/* curl share handle */
	CURLSH *handle;

	/* list of callbacks */
	callback_t cb[ CB_SHARE_LAST ];
};


static void
perl_curl_share_register_callback( pTHX_ perl_curl_share_t *share, SV **callback,
		SV *function )
{
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
}

/* make a new share */
static perl_curl_share_t *
perl_curl_share_new( void )
{
	perl_curl_share_t *share;
	Newxz( share, 1, perl_curl_share_t );
	share->handle = curl_share_init();
	return share;
}

/* delete the share */
static void
perl_curl_share_delete( pTHX_ perl_curl_share_t *share )
{
	perl_curl_share_callback_code_t i;
	if ( share->handle )
		curl_share_cleanup( share->handle );

	for ( i = 0; i < CB_SHARE_LAST; i++ ) {
		sv_2mortal( share->cb[i].func );
		sv_2mortal( share->cb[i].data );
	}
	Safefree( share );
}


static void
cb_share_lock( CURL *easy_handle, curl_lock_data data, curl_lock_access locktype,
		void *userptr )
{
	dTHX;
	dSP;

	int count;
	perl_curl_share_t *share;
	perl_curl_easy_t *easy;

	share = (perl_curl_share_t *) userptr;
	(void) curl_easy_getinfo( easy_handle, CURLINFO_PRIVATE, (void *) &easy );

	ENTER;
	SAVETMPS;
	PUSHMARK( sp );

	/* $easy, $data, $locktype, $userdata */
	XPUSHs( sv_2mortal( newSVsv( easy->perl_self ) ) );
	XPUSHs( sv_2mortal( newSViv( data ) ) );
	XPUSHs( sv_2mortal( newSViv( locktype ) ) );
	if ( share->cb[CB_SHARE_LOCK].data ) {
		XPUSHs( sv_2mortal( newSVsv( share->cb[CB_SHARE_LOCK].data ) ) );
	} else {
		XPUSHs( &PL_sv_undef );
	}

	PUTBACK;
	count = perl_call_sv( share->cb[CB_SHARE_LOCK].func, G_SCALAR );
	SPAGAIN;

	if ( count != 0 )
		croak( "callback for CURLSHOPT_LOCKFUNCTION didn't return void\n" );

	PUTBACK;
	FREETMPS;
	LEAVE;
	return;
}

static void
cb_share_unlock( CURL *easy_handle, curl_lock_data data, void *userptr )
{
	dTHX;
	dSP;

	int count;
	perl_curl_share_t *share;
	perl_curl_easy_t *easy;

	share = (perl_curl_share_t *) userptr;
	(void) curl_easy_getinfo( easy_handle, CURLINFO_PRIVATE, (void *) &easy );

	ENTER;
	SAVETMPS;
	PUSHMARK( sp );

	/* $easy, $data, $userdata */
	XPUSHs( sv_2mortal( newSVsv( easy->perl_self ) ) );
	XPUSHs( sv_2mortal( newSViv( data ) ) );
	if ( share->cb[CB_SHARE_LOCK].data ) {
		XPUSHs( sv_2mortal( newSVsv( share->cb[CB_SHARE_LOCK].data ) ) );
	} else {
		XPUSHs( &PL_sv_undef );
	}

	PUTBACK;
	count = perl_call_sv( share->cb[CB_SHARE_LOCK].func, G_SCALAR );
	SPAGAIN;

	if ( count != 0 )
		croak( "callback for CURLSHOPT_UNLOCKFUNCTION didn't return void\n" );

	PUTBACK;
	FREETMPS;
	LEAVE;
	return;
}

/* XS_SECTION */
#ifdef XS_SECTION

MODULE = WWW::CurlOO	PACKAGE = WWW::CurlOO::Share	PREFIX = curl_share_

INCLUDE: const-share-xs.inc

PROTOTYPES: ENABLE

void
curl_share_new( sclass="WWW::CurlOO::Share", base=HASHREF_BY_DEFAULT )
	const char *sclass
	SV *base
	PREINIT:
		perl_curl_share_t *share;
		HV *stash;
	PPCODE:
		if ( ! SvOK( base ) || ! SvROK( base ) )
			croak( "object base must be a valid reference\n" );

		share = perl_curl_share_new();
		perl_curl_setptr( aTHX_ base, share );

		stash = gv_stashpv( sclass, 0 );
		ST(0) = sv_bless( base, stash );

		XSRETURN(1);


void
curl_share_DESTROY( share )
	WWW::CurlOO::Share share
	CODE:
		perl_curl_share_delete( aTHX_ share );

int
curl_share_setopt( share, option, value )
	WWW::CurlOO::Share share
	int option
	SV * value
	CODE:
		/* {{{ */
		RETVAL = CURLE_OK;
		switch ( option ) {
			case CURLSHOPT_LOCKFUNC:
				RETVAL = curl_share_setopt( share->handle,
					CURLSHOPT_LOCKFUNC, SvOK( value ) ? cb_share_lock : NULL );
				curl_share_setopt( share->handle,
					CURLSHOPT_USERDATA, SvOK( value ) ? share : NULL );
				perl_curl_share_register_callback( aTHX_ share,
					&(share->cb[CB_SHARE_LOCK].func), value );
				break;
			case CURLSHOPT_UNLOCKFUNC:
				RETVAL = curl_share_setopt( share->handle,
					CURLSHOPT_UNLOCKFUNC, SvOK( value ) ? cb_share_unlock : NULL );
				curl_share_setopt( share->handle,
					CURLSHOPT_USERDATA, SvOK( value ) ? share : NULL );
				perl_curl_share_register_callback( aTHX_ share,
					&(share->cb[CB_SHARE_UNLOCK].func), value );
				break;
			case CURLSHOPT_USERDATA:
				perl_curl_share_register_callback( aTHX_ share,
					&(share->cb[CB_SHARE_LOCK].data), value );
				break;
			case CURLSHOPT_SHARE:
			case CURLSHOPT_UNSHARE:
				RETVAL = curl_share_setopt( share->handle, option, (long) SvIV( value ) );
				break;
			default:
				croak( "Unknown curl share option" );
				break;
		};
		/* }}} */
	OUTPUT:
		RETVAL


SV *
curl_share_strerror( share, errornum )
	WWW::CurlOO::Share share
	int errornum
	PREINIT:
		const char *errstr;
		(void) share; /* unused */
	CODE:
		errstr = curl_share_strerror( errornum );
		RETVAL = newSVpv( errstr, 0 );
	OUTPUT:
		RETVAL

#endif
