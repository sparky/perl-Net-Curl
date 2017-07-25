/* vim: ts=4:sw=4:ft=xs:fdm=marker
 *
 * Copyright 2011-2015 (C) Przemyslaw Iskra <sparky at pld-linux.org>
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

	/* list of data assigned to sockets */
	/* key: socket fd; value: user sv */
	simplell_t *socket_data;

	/* list of easy handles attached to this multi */
	/* key: our easy pointer, value: easy SV */
	simplell_t *easies;
};

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

	if ( multi->handle ) {
		curl_multi_setopt( multi->handle, CURLMOPT_SOCKETFUNCTION, NULL );
#ifdef CURLMOPT_TIMERFUNCTION
		curl_multi_setopt( multi->handle, CURLMOPT_TIMERFUNCTION, NULL );
#endif
	}

	/* remove and mortalize all easy handles */
	if ( multi->easies ) {
		simplell_t *next, *now = multi->easies;
		do {
			perl_curl_easy_t *easy;
			easy = INT2PTR( perl_curl_easy_t *, now->key );
			curl_multi_remove_handle( multi->handle, easy->handle );
			easy->multi = NULL;

			next = now->next;
			sv_2mortal( (SV *) now->value );
			Safefree( now );
		} while ( ( now = next ) != NULL );
	}

	if ( multi->handle )
		curl_multi_cleanup( multi->handle );

	SIMPLELL_FREE( multi->socket_data, sv_2mortal );

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

	/* $multi, $easy, $socket, $what, $socketdata, $userdata */
	SV *args[] = {
		/* 0 */ SELF2PERL( multi ),
		/* 1 */ SELF2PERL( easy ),
		/* 2 */ newSVuv( s ),
		/* 3 */ newSViv( what ),
		/* 4 */ &PL_sv_undef
	};
	if ( socketp )
		args[4] = newSVsv( (SV *) socketp );

	return PERL_CURL_CALL( &multi->cb[ CB_MULTI_SOCKET ], args );
} /*}}}*/

static int
cb_multi_timer( CURLM *multi_handle, long timeout_ms, void *userptr )
/*{{{*/ {
	dTHX;

	perl_curl_multi_t *multi;
	multi = (perl_curl_multi_t *) userptr;

	/* $multi, $timeout, $userdata */
	SV *args[] = {
		SELF2PERL( multi ),
		newSViv( timeout_ms )
	};

	return PERL_CURL_CALL( &multi->cb[ CB_MULTI_TIMER ], args );
} /*}}}*/

#ifdef CALLBACK_TYPECHECK
static curl_socket_callback pct_socket __attribute__((unused)) = cb_multi_socket;
static curl_multi_timer_callback pct_timer __attribute__((unused)) = cb_multi_timer;
#endif

static int
perl_curl_multi_magic_free( pTHX_ SV *sv, MAGIC *mg )
{
	if ( mg->mg_ptr ) {
		/* prevent recursive destruction */
		SvREFCNT( sv ) = 1 << 30;

		perl_curl_multi_delete( aTHX_ (void *) mg->mg_ptr );

		SvREFCNT( sv ) = 0;
	}
	return 0;
}

char **
perl_curl_multi_blacklist( pTHX_ SV *arrayref )
{
	AV *array;
	int array_len, i;
	char **blacklist;

	if ( !SvOK( arrayref ) )
		return NULL;
	if ( !SvROK( arrayref ) )
		croak( "not an array" );

	array = (AV *) SvRV( arrayref );
	array_len = av_len( array );
	if ( array_len == -1 )
		return NULL;

	Newxz( blacklist, array_len + 2, char * );

	for ( i = 0; i <= array_len; i++ ) {
		SV **sv;

		sv = av_fetch( array, i, 0 );
		if ( !SvOK( *sv ) )
			continue;
		blacklist[i] = SvPV_nolen( *sv );
	}

	return blacklist;
}

static MGVTBL perl_curl_multi_vtbl = {
	NULL, NULL, NULL, NULL
	,perl_curl_multi_magic_free
	,NULL
	,perl_curl_any_magic_nodup
#ifdef MGf_LOCAL
	,NULL
#endif
};


#define MULTI_DIE( ret )		\
	STMT_START {				\
		CURLMcode code = (ret);	\
		if ( code != CURLM_OK )	\
			die_code( "Multi", code ); \
	} STMT_END


MODULE = Net::Curl	PACKAGE = Net::Curl::Multi

INCLUDE: const-multi-xs.inc

PROTOTYPES: ENABLE

void
new( sclass="Net::Curl::Multi", base=HASHREF_BY_DEFAULT )
	const char *sclass
	SV *base
	PREINIT:
		perl_curl_multi_t *multi;
		HV *stash;
	PPCODE:
		if ( ! SvOK( base ) || ! SvROK( base ) )
			croak( "object base must be a valid reference\n" );

		multi = perl_curl_multi_new();
		perl_curl_setptr( aTHX_ base, &perl_curl_multi_vtbl, multi );

		/* those must be set or else socket_action() segfaults */
		curl_multi_setopt( multi->handle, CURLMOPT_SOCKETFUNCTION,
			cb_multi_socket );
		curl_multi_setopt( multi->handle, CURLMOPT_SOCKETDATA, multi );

		stash = gv_stashpv( sclass, 0 );
		ST(0) = sv_bless( base, stash );

		multi->perl_self = SvRV( ST(0) );

		XSRETURN(1);


void
add_handle( multi, easy )
	Net::Curl::Multi multi
	Net::Curl::Easy easy
	PREINIT:
		CURLMcode ret;
	CODE:
		if ( easy->multi )
			croak( "Specified easy handle is attached to %s multi handle already",
				easy->multi == multi ? "this" : "another" );

		ret = curl_multi_add_handle( multi->handle, easy->handle );
		if ( !ret ) {
			SV **easysv_ptr;
			easysv_ptr = perl_curl_simplell_add( aTHX_ &multi->easies,
				PTR2nat( easy ) );
			*easysv_ptr = SELF2PERL( easy );
			easy->multi = multi;
		}
		MULTI_DIE( ret );

void
remove_handle( multi, easy )
	Net::Curl::Multi multi
	Net::Curl::Easy easy
	PREINIT:
		CURLMcode ret;
	CODE:
		CLEAR_ERRSV();
		if ( easy->multi != multi )
			croak( "Specified easy handle is not attached to %s multi handle",
				easy->multi ? "this" : "any" );

		ret = curl_multi_remove_handle( multi->handle, easy->handle );
		{
			SV *easysv;
			easysv = perl_curl_simplell_del( aTHX_ &multi->easies,
				PTR2nat( easy ) );
			if ( !easysv )
				croak( "internal Net::Curl error" );
			sv_2mortal( easysv );
		}
		easy->multi = NULL;

		/* rethrow errors */
		if ( SvTRUE( ERRSV ) )
			croak( NULL );

		MULTI_DIE( ret );


void
info_read( multi )
	Net::Curl::Multi multi
	PREINIT:
		int queue;
		CURLMsg *msg;
	PPCODE:
		CLEAR_ERRSV();
		while ( (msg = curl_multi_info_read( multi->handle, &queue ) ) ) {
			/* most likely CURLMSG_DONE */
			if ( msg->msg != CURLMSG_NONE && msg->msg != CURLMSG_LAST ) {
				Net__Curl__Easy easy;
				SV *errsv;

				curl_easy_getinfo( msg->easy_handle,
					CURLINFO_PRIVATE, (void *) &easy );

				EXTEND( SP, 3 );
				mPUSHs( newSViv( msg->msg ) );
				mPUSHs( SELF2PERL( easy ) );

				errsv = sv_newmortal();
				sv_setref_iv( errsv, "Net::Curl::Easy::Code",
					msg->data.result );
				PUSHs( errsv );

				/* cannot rethrow errors, because we want to make sure we
				 * return the easy, but $@ should be set */

				XSRETURN( 3 );
			}

			/* rethrow errors */
			if ( SvTRUE( ERRSV ) )
				croak( NULL );
		};

		/* rethrow errors */
		if ( SvTRUE( ERRSV ) )
			croak( NULL );

		XSRETURN_EMPTY;


void
fdset( multi )
	Net::Curl::Multi multi
	PREINIT:
		CURLMcode ret;
		fd_set fdread, fdwrite, fdexcep;
		int maxfd, i;
		int readsize, writesize, excepsize;
		unsigned char readset[ sizeof( fd_set ) ] = { 0 };
		unsigned char writeset[ sizeof( fd_set ) ] = { 0 };
		unsigned char excepset[ sizeof( fd_set ) ] = { 0 };
	PPCODE:
		FD_ZERO( &fdread );
		FD_ZERO( &fdwrite );
		FD_ZERO( &fdexcep );

		ret = curl_multi_fdset( multi->handle,
			&fdread, &fdwrite, &fdexcep, &maxfd );
		MULTI_DIE( ret );

		readsize = writesize = excepsize = 0;

		/* TODO: this is rather slow, should copy whole bytes instead, but
		 * some fdset implementations may be hard to predict */
		if ( maxfd != -1 ) {
			for ( i = 0; i <= maxfd; i++ ) {
				if ( FD_ISSET( i, &fdread ) ) {
					readsize = i / 8 + 1;
					readset[ i / 8 ] |= 1 << ( i % 8 );
				}
				if ( FD_ISSET( i, &fdwrite ) ) {
					writesize = i / 8 + 1;
					writeset[ i / 8 ] |= 1 << ( i % 8 );
				}
				if ( FD_ISSET( i, &fdexcep ) ) {
					excepsize = i / 8 + 1;
					excepset[ i / 8 ] |= 1 << ( i % 8 );
				}
			}
		}

		EXTEND( SP, 3 );
		mPUSHs( newSVpvn( (char *) readset, readsize ) );
		mPUSHs( newSVpvn( (char *) writeset, writesize ) );
		mPUSHs( newSVpvn( (char *) excepset, excepsize ) );


long
timeout( multi )
	Net::Curl::Multi multi
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
setopt( multi, option, value )
	Net::Curl::Multi multi
	int option
	SV *value
	PREINIT:
		CURLMcode ret1 = CURLM_OK, ret2 = CURLM_OK;
		char **blacklist;
	CODE:
		switch ( option ) {
			case CURLMOPT_SOCKETDATA:
				SvREPLACE( multi->cb[ CB_MULTI_SOCKET ].data, value );
				break;

			case CURLMOPT_SOCKETFUNCTION:
				SvREPLACE( multi->cb[ CB_MULTI_SOCKET ].func, value );
				break;

			/* introduced in 7.16.0 */
#ifdef CURLMOPT_TIMERDATA
#ifdef CURLMOPT_TIMERFUNCTION
			case CURLMOPT_TIMERDATA:
				SvREPLACE( multi->cb[ CB_MULTI_TIMER ].data, value );
				break;

			case CURLMOPT_TIMERFUNCTION:
				SvREPLACE( multi->cb[ CB_MULTI_TIMER ].func, value );
				ret2 = curl_multi_setopt( multi->handle, CURLMOPT_TIMERFUNCTION,
					SvOK( value ) ? cb_multi_timer : NULL );
				ret1 = curl_multi_setopt( multi->handle, CURLMOPT_TIMERDATA, multi );
				break;
#endif
#endif

			/* introduced in 7.30.0 */
#ifdef CURLMOPT_PIPELINING_SERVER_BL
#ifdef CURLMOPT_PIPELINING_SITE_BL
			case CURLMOPT_PIPELINING_SERVER_BL:
			case CURLMOPT_PIPELINING_SITE_BL:
				blacklist = perl_curl_multi_blacklist( aTHX_ value );
				ret1 = curl_multi_setopt( multi->handle, option, blacklist );
				if ( blacklist )
					Safefree( blacklist );
				break;
#endif
#endif

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
perform( multi )
	Net::Curl::Multi multi
	PREINIT:
		int remaining;
		CURLMcode ret;
	CODE:
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


#if LIBCURL_VERSION_NUM >= 0x071C00

int
wait( multi, ... )
	Net::Curl::Multi multi
	PROTOTYPE: $;$$
	PREINIT:
		int timeout = -1;
		SV *extra_fds = NULL;
		int remaining;
		CURLMcode ret;
		struct curl_waitfd *wait_for = NULL;
		unsigned int extra_nfds = 0;
	CODE:
		CLEAR_ERRSV();

		if ( items > 1 )
			timeout = SvIV( ST( items - 1 ) );
		if ( items > 2 )
			extra_fds = ST( 1 );

		if ( extra_fds && SvOK( extra_fds ) )
		{
			int i;
			AV *array;
			if ( !SvROK( extra_fds ) || SvTYPE( SvRV( extra_fds ) ) != SVt_PVAV )
				croak( "must be an arrayref" );
			array = (AV *) SvRV( extra_fds );
			extra_nfds = 1 + av_len( array );

			Newxz( wait_for, extra_nfds, struct curl_waitfd );

			for ( i = 0; i < extra_nfds; i++ )
			{
				HV *hash;
				SV **tmp, **sv;
				sv = av_fetch( array, i, 0 );
				if ( !SvOK( *sv ) )
					continue;
				if ( !SvROK( *sv ) || SvTYPE( SvRV( *sv ) ) != SVt_PVHV )
					croak( "must be a hashref" );
				hash = (HV *) SvRV( *sv );

				tmp = hv_fetchs( hash, "fd", 0 );
				if ( tmp && *tmp && SvOK( *tmp ) )
					wait_for[i].fd = SvIV( *tmp );

				tmp = hv_fetchs( hash, "events", 0 );
				if ( tmp && *tmp && SvOK( *tmp ) )
					wait_for[i].events = SvIV( *tmp );

				/* there is also revents which will be returned by curl */
				tmp = hv_fetchs( hash, "revents", 0 );
				if ( tmp && *tmp && SvOK( *tmp ) )
					wait_for[i].revents = SvIV( *tmp );
			}
		}

		ret = curl_multi_wait( multi->handle, wait_for, extra_nfds, timeout,
			&remaining );

		if ( wait_for )
		{
			int i;
			AV *array = (AV *) SvRV( extra_fds );
			for ( i = 0; i < extra_nfds; i++ )
			{
				HV *hash;
				SV **sv;
				short revents = wait_for[i].revents;
				sv = av_fetch( array, i, 0 );
				hash = (HV *) SvRV( *sv );

				(void) hv_stores( hash, "revents", newSViv( revents ) );
			}

			Safefree( wait_for );
		}

		/* rethrow errors */
		if ( SvTRUE( ERRSV ) )
			croak( NULL );

		MULTI_DIE( ret );

		RETVAL = remaining;
	OUTPUT:
		RETVAL

#endif


int
socket_action( multi, sockfd=CURL_SOCKET_BAD, ev_bitmask=0 )
	Net::Curl::Multi multi
	int sockfd
	int ev_bitmask
	PREINIT:
		int remaining;
		CURLMcode ret;
	CODE:
		CLEAR_ERRSV();
		do {
#ifdef CURL_CSELECT_IN
			ret = curl_multi_socket_action( multi->handle,
				(curl_socket_t) sockfd, ev_bitmask, &remaining );
#else
			ret = curl_multi_socket( multi->handle,
				(curl_socket_t) sockfd, &remaining );
#endif
		} while ( ret == CURLM_CALL_MULTI_PERFORM );

		/* rethrow errors */
		if ( SvTRUE( ERRSV ) )
			croak( NULL );

		MULTI_DIE( ret );

		RETVAL = remaining;
	OUTPUT:
		RETVAL


#if LIBCURL_VERSION_NUM >= 0x070f05

void
assign( multi, sockfd, value=NULL )
	Net::Curl::Multi multi
	unsigned long sockfd
	SV *value
	PREINIT:
		CURLMcode ret;
		void *sockptr;
	CODE:
		if ( value && SvOK( value ) ) {
			SV **valueptr;
			valueptr = perl_curl_simplell_add( aTHX_ &multi->socket_data,
				sockfd );
			if ( !valueptr )
				croak( "internal Net::Curl error" );
			if ( *valueptr )
				sv_2mortal( *valueptr );
			sockptr = *valueptr = newSVsv( value );
		} else {
			SV *oldvalue;
			oldvalue = perl_curl_simplell_del( aTHX_ &multi->socket_data, sockfd );
			if ( oldvalue )
				sv_2mortal( oldvalue );
			sockptr = NULL;
		}
		ret = curl_multi_assign( multi->handle, sockfd, sockptr );
		MULTI_DIE( ret );

#endif


SV *
strerror( ... )
	PROTOTYPE: $;$
	PREINIT:
		const char *errstr;
	CODE:
		if ( items < 1 || items > 2 )
			croak( "Usage: Net::Curl::Multi::strerror( [multi], errnum )" );
		errstr = curl_multi_strerror( SvIV( ST( items - 1 ) ) );
		RETVAL = newSVpv( errstr, 0 );
	OUTPUT:
		RETVAL


# /* Extensions: Functions that do not have libcurl equivalents. */


void
handles( multi )
	Net::Curl::Multi multi
	PREINIT:
			simplell_t *now;
	PPCODE:
		if ( GIMME_V == G_VOID )
			XSRETURN( 0 );

		now = multi->easies;

		if ( GIMME_V == G_SCALAR ) {
			IV i = 0;
			while ( now ) {
				i++;
				now = now->next;
			}
			ST(0) = newSViv( i );
			XSRETURN( 1 );
		}
		while ( now ) {
			XPUSHs( newSVsv( now->value ) );
			now = now->next;
		}


int
CLONE_SKIP( pkg )
	SV *pkg
	CODE:
		(void ) pkg;
		RETVAL = 1;
	OUTPUT:
		RETVAL
