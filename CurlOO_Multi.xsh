/* vim: ts=4:sw=4:ft=xs:fdm=marker: */
/*
 * Copyright 2011 (C) Przemyslaw Iskra <sparky at pld-linux.org>
 *
 * Loosely based on code by Cris Bailiff <c.bailiff+curl at devsecure.com>,
 * and subsequent fixes by other contributors.
 */


typedef enum {
	CB_MULTI_SOCKET = 0,
	CB_MULTI_TIMER,
	CB_MULTI_LAST,
} perl_curl_multi_callback_code_t;

struct perl_curl_multi_s {
	/* last seen version of this object */
	SV *perl_self;

	/* curl multi handle */
	CURLM *handle;

	/* list of callbacks */
	callback_t cb[ CB_MULTI_LAST ];
};

static void
perl_curl_multi_register_callback( pTHX_ perl_curl_multi_t *multi, SV **callback, SV *function )
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

/* make a new multi */
static perl_curl_multi_t *
perl_curl_multi_new( void )
/*{{{*/ {
	perl_curl_multi_t *multi;
	Newxz( multi, 1, perl_curl_multi_t );
	multi->handle = curl_multi_init();
	return multi;
} /*}}}*/

/* delete the multi */
static void
perl_curl_multi_delete( pTHX_ perl_curl_multi_t *multi )
/*{{{*/ {
	perl_curl_multi_callback_code_t i;

	if ( multi->handle )
		curl_multi_cleanup( multi->handle );

	for( i = 0; i < CB_MULTI_LAST; i++ ) {
		sv_2mortal( multi->cb[i].func );
		sv_2mortal( multi->cb[i].data );
	}

	Safefree( multi );
} /*}}}*/

static int
cb_multi_socket( CURL *easy_handle, curl_socket_t s, int what, void *userptr,
		void *socketp )
/*{{{*/ {
	dTHX;
	dSP;

	int count;
	perl_curl_multi_t *multi;
	perl_curl_easy_t *easy;

	multi = (perl_curl_multi_t *) userptr;
	(void) curl_easy_getinfo( easy_handle, CURLINFO_PRIVATE, (void *) &easy );

	ENTER;
	SAVETMPS;
	PUSHMARK( sp );

	/* $easy, $socket, $what, $userdata */
	/* XXX: add $socketdata */
	XPUSHs( sv_2mortal( newSVsv( easy->perl_self ) ) );
	XPUSHs( sv_2mortal( newSVuv( s ) ) );
	XPUSHs( sv_2mortal( newSViv( what ) ) );
	if ( multi->cb[CB_MULTI_SOCKET].data ) {
		XPUSHs( sv_2mortal( newSVsv( multi->cb[CB_MULTI_SOCKET].data ) ) );
	} else {
		XPUSHs( &PL_sv_undef );
	}

	PUTBACK;
	count = perl_call_sv( multi->cb[CB_MULTI_SOCKET].func, G_SCALAR );
	SPAGAIN;

	if ( count != 1 )
		croak( "callback for CURLMOPT_SOCKETFUNCTION didn't return 1\n" );

	count = POPi;

	PUTBACK;
	FREETMPS;
	LEAVE;
	return count;
} /*}}}*/

static int
cb_multi_timer( CURLM *multi_handle, long timeout_ms, void *userptr )
/*{{{*/ {
	dTHX;
	dSP;

	int count;
	perl_curl_multi_t *multi;
	multi = (perl_curl_multi_t *) userptr;

	ENTER;
	SAVETMPS;
	PUSHMARK( sp );

	/* $multi, $timeout, $userdata */
	XPUSHs( sv_2mortal( newSVsv( multi->perl_self ) ) );
	XPUSHs( sv_2mortal( newSViv( timeout_ms ) ) );
	if ( multi->cb[CB_MULTI_TIMER].data )
		XPUSHs( sv_2mortal( newSVsv( multi->cb[CB_MULTI_TIMER].data ) ) );

	PUTBACK;
	count = perl_call_sv( multi->cb[CB_MULTI_TIMER].func, G_SCALAR );
	SPAGAIN;

	if ( count != 1 )
		croak( "callback for CURLMOPT_TIMERFUNCTION didn't return 1\n" );

	count = POPi;

	PUTBACK;
	FREETMPS;
	LEAVE;
	return count;
} /*}}}*/


/* XS_SECTION */
#ifdef XS_SECTION

MODULE = WWW::CurlOO	PACKAGE = WWW::CurlOO::Multi	PREFIX = curl_multi_

INCLUDE: const-multi-xs.inc

PROTOTYPES: ENABLE

void
curl_multi_new( sclass="WWW::CurlOO::Multi", base=HASHREF_BY_DEFAULT )
	const char *sclass
	SV *base
	PREINIT:
		perl_curl_multi_t *multi;
		HV *stash;
	PPCODE:
		if ( ! SvOK( base ) || ! SvROK( base ) )
			croak( "object base must be a valid reference\n" );

		multi = perl_curl_multi_new();
		perl_curl_setptr( aTHX_ base, multi );

		stash = gv_stashpv( sclass, 0 );
		ST(0) = sv_bless( base, stash );

		XSRETURN(1);


void
curl_multi_add_handle( multi, easy )
	WWW::CurlOO::Multi multi
	WWW::CurlOO::Easy easy
	CODE:
		multi->perl_self = sv_2mortal( newSVsv( ST(0) ) );
		perl_curl_easy_update( easy, newSVsv( ST(1) ) );
		easy->multi = multi;
		curl_multi_add_handle( multi->handle, easy->handle );

void
curl_multi_remove_handle( multi, easy )
	WWW::CurlOO::Multi multi
	WWW::CurlOO::Easy easy
	CODE:
		multi->perl_self = sv_2mortal( newSVsv( ST(0) ) );
		curl_multi_remove_handle( multi->handle, easy->handle );
		sv_2mortal( easy->perl_self );
		easy->perl_self = NULL;
		easy->multi = NULL;

void
curl_multi_info_read( multi )
	WWW::CurlOO::Multi multi
	PREINIT:
		CURL *easy_handle = NULL;
		CURLcode res;
		WWW__CurlOO__Easy easy;
		int queue;
		CURLMsg *msg;
	PPCODE:
		/* {{{ */
		multi->perl_self = sv_2mortal( newSVsv( ST(0) ) );
		while ( (msg = curl_multi_info_read( multi->handle, &queue ) ) ) {
			if ( msg->msg == CURLMSG_DONE ) {
				easy_handle = msg->easy_handle;
				res = msg->data.result;
				break;
			}
		};
		if ( easy_handle ) {
			curl_easy_getinfo( easy_handle, CURLINFO_PRIVATE, (void *) &easy );
			curl_multi_remove_handle( multi->handle, easy_handle );
			XPUSHs( sv_2mortal( easy->perl_self ) );
			easy->perl_self = NULL;
			easy->multi = NULL;
			XPUSHs( sv_2mortal( newSViv( res ) ) );
		} else {
			XSRETURN_EMPTY;
		}
		/* }}} */


void
curl_multi_fdset( multi )
	WWW::CurlOO::Multi multi
	PREINIT:
		fd_set fdread, fdwrite, fdexcep;
		int maxfd, i, vecsize;
		unsigned char readset[ sizeof( fd_set ) ] = { 0 };
		unsigned char writeset[ sizeof( fd_set ) ] = { 0 };
		unsigned char excepset[ sizeof( fd_set ) ] = { 0 };
	PPCODE:
		/* {{{ */
		FD_ZERO( &fdread );
		FD_ZERO( &fdwrite );
		FD_ZERO( &fdexcep );

		curl_multi_fdset( multi->handle, &fdread, &fdwrite, &fdexcep, &maxfd );
		vecsize = ( maxfd + 8 ) / 8;

		if ( maxfd != -1 ) {
			for ( i = 0; i <= maxfd; i++ ) {
				if ( FD_ISSET( i, &fdread ) )
					readset[ i / 8 ] |= 1 << ( i % 8 );
				if ( FD_ISSET( i, &fdwrite ) )
					writeset[ i / 8 ] |= 1 << ( i % 8 );
				if ( FD_ISSET( i, &fdexcep ) )
					excepset[ i / 8 ] |= 1 << ( i % 8 );
			}
		}
		XPUSHs( sv_2mortal( newSVpvn( (char *) readset, vecsize ) ) );
		XPUSHs( sv_2mortal( newSVpvn( (char *) writeset, vecsize ) ) );
		XPUSHs( sv_2mortal( newSVpvn( (char *) excepset, vecsize ) ) );
		/* }}} */


long
curl_multi_timeout( multi )
	WWW::CurlOO::Multi multi
	PREINIT:
		long timeout;
		CURLMcode ret;
	CODE:
		ret = curl_multi_timeout( multi->handle, &timeout );
		if ( ret != CURLM_OK )
			croak( "curl_multi_timeout() failed: %d\n", ret );

		RETVAL = timeout;
	OUTPUT:
		RETVAL

int
curl_multi_setopt( multi, option, value )
	WWW::CurlOO::Multi multi
	int option
	SV *value
	CODE:
		/* {{{ */
		RETVAL = CURLM_OK;
		switch ( option ) {
			case CURLMOPT_SOCKETFUNCTION:
			case CURLMOPT_SOCKETDATA:
				curl_multi_setopt( multi->handle, CURLMOPT_SOCKETFUNCTION, SvOK( value ) ? cb_multi_socket : NULL );
				curl_multi_setopt( multi->handle, CURLMOPT_SOCKETDATA, SvOK( value ) ? multi : NULL );
				perl_curl_multi_register_callback( aTHX_ multi,
					option == CURLMOPT_SOCKETDATA ?
						&( multi->cb[CB_MULTI_SOCKET].data ) :
						&( multi->cb[CB_MULTI_SOCKET].func ),
					value );
				break;
			case CURLMOPT_TIMERFUNCTION:
			case CURLMOPT_TIMERDATA:
				curl_multi_setopt( multi->handle, CURLMOPT_TIMERFUNCTION, SvOK( value ) ? cb_multi_timer : NULL );
				curl_multi_setopt( multi->handle, CURLMOPT_TIMERDATA, SvOK( value ) ? multi : NULL );
				perl_curl_multi_register_callback( aTHX_ multi,
					option == CURLMOPT_TIMERDATA ?
						&( multi->cb[CB_MULTI_TIMER].data ) :
						&( multi->cb[CB_MULTI_TIMER].func ),
					value );
				break;

			/* default cases */
			default:
				if ( option < CURLOPTTYPE_OBJECTPOINT ) { /* A long (integer) value */
					RETVAL = curl_multi_setopt( multi->handle, option, (long) SvIV( value ) );
				} else {
					croak( "Unknown curl multi option" );
				}
				break;
		};
		/* }}} */
	OUTPUT:
		RETVAL


int
curl_multi_perform( multi )
	WWW::CurlOO::Multi multi
	PREINIT:
		int remaining;
	CODE:
		multi->perl_self = sv_2mortal( newSVsv( ST(0) ) );
		while( CURLM_CALL_MULTI_PERFORM ==
				curl_multi_perform( multi->handle, &remaining ) )
			;
		RETVAL = remaining;
	OUTPUT:
		RETVAL

int
curl_multi_socket_action( multi, sockfd=CURL_SOCKET_BAD, ev_bitmask=0 )
	WWW::CurlOO::Multi multi
	int sockfd
	int ev_bitmask
	PREINIT:
		int remaining;
	CODE:
		multi->perl_self = sv_2mortal( newSVsv( ST(0) ) );
		while( CURLM_CALL_MULTI_PERFORM == curl_multi_socket_action(
				multi->handle, (curl_socket_t) sockfd, ev_bitmask, &remaining ) )
			;
		RETVAL = remaining;
	OUTPUT:
		RETVAL


void
curl_multi_DESTROY( multi )
	WWW::CurlOO::Multi multi
	CODE:
		/* TODO: remove all associated easy handles */
		perl_curl_multi_delete( aTHX_ multi );

SV *
curl_multi_strerror( multi, errornum )
	WWW::CurlOO::Multi multi
	int errornum
	PREINIT:
		const char *errstr;
		(void) multi; /* unused */
	CODE:
		errstr = curl_multi_strerror( errornum );
		RETVAL = newSVpv( errstr, 0 );
	OUTPUT:
		RETVAL

#endif
