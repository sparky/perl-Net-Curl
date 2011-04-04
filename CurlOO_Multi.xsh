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

	perl_curl_multi_t *multi;
	perl_curl_easy_t *easy;

	multi = (perl_curl_multi_t *) userptr;
	(void) curl_easy_getinfo( easy_handle, CURLINFO_PRIVATE, (void *) &easy );

	/* $easy, $socket, $what, $userdata */
	/* XXX: add $socketdata */
	SV *args[] = {
		newSVsv( easy->perl_self ),
		newSVuv( s ),
		newSViv( what ),
		NULL
	};
	int argn = 3;

	if ( multi->cb[CB_MULTI_SOCKET].data )
		args[ argn++ ] = newSVsv( multi->cb[CB_MULTI_SOCKET].data );

	return perl_curl_call( aTHX_ multi->cb[CB_MULTI_SOCKET].func, argn, args );
} /*}}}*/

static int
cb_multi_timer( CURLM *multi_handle, long timeout_ms, void *userptr )
/*{{{*/ {
	dTHX;

	perl_curl_multi_t *multi;
	multi = (perl_curl_multi_t *) userptr;

	/* $multi, $timeout, $userdata */
	SV *args[] = {
		newSVsv( multi->perl_self ),
		newSViv( timeout_ms ),
		NULL
	};
	int argn = 2;

	if ( multi->cb[CB_MULTI_TIMER].data )
		args[ argn++ ] = newSVsv( multi->cb[CB_MULTI_TIMER].data );

	return perl_curl_call( aTHX_ multi->cb[CB_MULTI_TIMER].func, argn, args );
} /*}}}*/


#define MULTI_DIE( ret )		\
	STMT_START {				\
		CURLMcode code = (ret);	\
		if ( code != CURLM_OK )	\
			die_dual( code, curl_multi_strerror( code ) ); \
	} STMT_END


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
	PREINIT:
		CURLMcode ret;
	CODE:
		multi->perl_self = sv_2mortal( newSVsv( ST(0) ) );
		perl_curl_easy_update( easy, newSVsv( ST(1) ) );
		easy->multi = multi;
		ret = curl_multi_add_handle( multi->handle, easy->handle );
		MULTI_DIE( ret );

void
curl_multi_remove_handle( multi, easy )
	WWW::CurlOO::Multi multi
	WWW::CurlOO::Easy easy
	PREINIT:
		CURLMcode ret;
	CODE:
		multi->perl_self = sv_2mortal( newSVsv( ST(0) ) );
		CLEAR_ERRSV();
		ret = curl_multi_remove_handle( multi->handle, easy->handle );
		sv_2mortal( easy->perl_self );
		easy->perl_self = NULL;
		easy->multi = NULL;

		/* rethrow errors */
		if ( SvTRUE( ERRSV ) )
			croak( NULL );

		MULTI_DIE( ret );


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
		CLEAR_ERRSV();
		while ( (msg = curl_multi_info_read( multi->handle, &queue ) ) ) {
			if ( msg->msg == CURLMSG_DONE ) {
				easy_handle = msg->easy_handle;
				res = msg->data.result;
				break;
			}
		};
		/* TODO: do not automatically remove the handle, because exceptions can mess
		 * things up */
		if ( easy_handle ) {
			CURLMcode ret;
			curl_easy_getinfo( easy_handle, CURLINFO_PRIVATE, (void *) &easy );
			ret = curl_multi_remove_handle( multi->handle, easy_handle );

			MULTI_DIE( ret );

			/* rethrow errors */
			if ( SvTRUE( ERRSV ) )
				croak( NULL );

			mXPUSHs( easy->perl_self );
			easy->perl_self = NULL;
			easy->multi = NULL;
			mXPUSHs( newSViv( res ) );
		} else {
			/* rethrow errors */
			if ( SvTRUE( ERRSV ) )
				croak( NULL );
			XSRETURN_EMPTY;
		}

		/* }}} */


void
curl_multi_fdset( multi )
	WWW::CurlOO::Multi multi
	PREINIT:
		CURLMcode ret;
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

		ret = curl_multi_fdset( multi->handle,
			&fdread, &fdwrite, &fdexcep, &maxfd );
		MULTI_DIE( ret );

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
		MULTI_DIE( ret );

		RETVAL = timeout;
	OUTPUT:
		RETVAL

void
curl_multi_setopt( multi, option, value )
	WWW::CurlOO::Multi multi
	int option
	SV *value
	PREINIT:
		CURLMcode ret1, ret2 = CURLM_OK;
	CODE:
		switch ( option ) {
			case CURLMOPT_SOCKETFUNCTION:
			case CURLMOPT_SOCKETDATA:
				ret2 = curl_multi_setopt( multi->handle, CURLMOPT_SOCKETFUNCTION,
					SvOK( value ) ? cb_multi_socket : NULL );
				ret1 = curl_multi_setopt( multi->handle, CURLMOPT_SOCKETDATA,
					SvOK( value ) ? multi : NULL );
				perl_curl_multi_register_callback( aTHX_ multi,
					option == CURLMOPT_SOCKETDATA ?
						&( multi->cb[CB_MULTI_SOCKET].data ) :
						&( multi->cb[CB_MULTI_SOCKET].func ),
					value );
				break;
			case CURLMOPT_TIMERFUNCTION:
			case CURLMOPT_TIMERDATA:
				ret2 = curl_multi_setopt( multi->handle, CURLMOPT_TIMERFUNCTION,
					SvOK( value ) ? cb_multi_timer : NULL );
				ret1 = curl_multi_setopt( multi->handle, CURLMOPT_TIMERDATA,
					SvOK( value ) ? multi : NULL );
				perl_curl_multi_register_callback( aTHX_ multi,
					option == CURLMOPT_TIMERDATA ?
						&( multi->cb[CB_MULTI_TIMER].data ) :
						&( multi->cb[CB_MULTI_TIMER].func ),
					value );
				break;

			/* default cases */
			default:
				if ( option < CURLOPTTYPE_OBJECTPOINT ) {
					/* A long (integer) value */
					ret1 = curl_multi_setopt( multi->handle, option,
						(long) SvIV( value ) );
				} else {
					croak( "Unknown curl multi option" );
				}
				break;
		};
		MULTI_DIE( ret2 );
		MULTI_DIE( ret1 );


int
curl_multi_perform( multi )
	WWW::CurlOO::Multi multi
	PREINIT:
		int remaining;
		CURLMcode ret;
	CODE:
		multi->perl_self = sv_2mortal( newSVsv( ST(0) ) );
		CLEAR_ERRSV();
		do {
			ret = curl_multi_perform( multi->handle, &remaining );
		} while ( ret == CURLM_CALL_MULTI_PERFORM );

		/* rethrow errors */
		if ( SvTRUE( ERRSV ) )
			croak( NULL );

		MULTI_DIE( ret );

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
		CURLMcode ret;
	CODE:
		multi->perl_self = sv_2mortal( newSVsv( ST(0) ) );
		CLEAR_ERRSV();
		do {
			ret = curl_multi_socket_action( multi->handle,
				(curl_socket_t) sockfd, ev_bitmask, &remaining );
		} while ( ret == CURLM_CALL_MULTI_PERFORM );

		/* rethrow errors */
		if ( SvTRUE( ERRSV ) )
			croak( NULL );

		MULTI_DIE( ret );

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
curl_multi_strerror( ... )
	PROTOTYPE: $;$
	PREINIT:
		const char *errstr;
	CODE:
		if ( items < 1 || items > 2 )
			croak_xs_usage(cv,  "[multi], errnum");
		errstr = curl_multi_strerror( SvIV( ST( items - 1 ) ) );
		RETVAL = newSVpv( errstr, 0 );
	OUTPUT:
		RETVAL
