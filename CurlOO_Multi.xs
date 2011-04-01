/* vim: ts=4:sw=4:fdm=marker: */
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
	CURLM *curlm;

	/* list of callbacks */
	callback_t cb[ CB_MULTI_LAST ];
};

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

	for(i=0;i<CB_MULTI_LAST;i++) {
		sv_2mortal(self->cb[i].func);
		sv_2mortal(self->cb[i].data);
	}

	Safefree(self);
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
	if (self->cb[CB_MULTI_SOCKET].data) {
		XPUSHs(sv_2mortal(newSVsv(self->cb[CB_MULTI_SOCKET].data)));
	} else {
		XPUSHs(&PL_sv_undef);
	}

	PUTBACK;
	count = perl_call_sv(self->cb[CB_MULTI_SOCKET].func, G_SCALAR);
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
	if ( self->cb[CB_MULTI_TIMER].data )
		XPUSHs( sv_2mortal( newSVsv( self->cb[CB_MULTI_TIMER].data ) ) );

	PUTBACK;
	count = perl_call_sv( self->cb[CB_MULTI_TIMER].func, G_SCALAR );
	SPAGAIN;

	if (count != 1)
		croak("callback for CURLMOPT_TIMERFUNCTION didn't return 1\n");

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
		perl_curl_multi_t *self;
		HV *stash;
	PPCODE:
		if ( ! SvOK( base ) || ! SvROK( base ) )
			croak( "object base must be a valid reference\n" );

		self = perl_curl_multi_new();
		perl_curl_setptr( aTHX_ base, self );

		stash = gv_stashpv( sclass, 0 );
		ST(0) = sv_bless( base, stash );

		XSRETURN(1);


void
curl_multi_add_handle(curlm, curl)
	WWW::CurlOO::Multi curlm
	WWW::CurlOO::Easy curl
	CODE:
		curlm->perl_self = ST(0);
		/* XXX: increase refcount */
		perl_curl_easy_update( curl, newSVsv( ST(1) ) );
		curl->multi = curlm;
		curl_multi_add_handle( curlm->curlm, curl->curl );

void
curl_multi_remove_handle(curlm, curl)
	WWW::CurlOO::Multi curlm
	WWW::CurlOO::Easy curl
	CODE:
		curl_multi_remove_handle(curlm->curlm, curl->curl);
		/* XXX: decrease refcount */
		sv_2mortal( curl->perl_self );
		curl->perl_self = NULL;
		curl->multi = NULL;

void
curl_multi_info_read(self)
	WWW::CurlOO::Multi self
	PREINIT:
		CURL *easy = NULL;
		CURLcode res;
		WWW__CurlOO__Easy peasy;
		int queue;
		CURLMsg *msg;
	PPCODE:
		/* {{{ */
		while ((msg = curl_multi_info_read(self->curlm, &queue))) {
			if ( msg->msg == CURLMSG_DONE) {
				easy = msg->easy_handle;
				res = msg->data.result;
				break;
			}
		};
		if (easy) {
			curl_easy_getinfo( easy, CURLINFO_PRIVATE, (void *)&peasy );
			curl_multi_remove_handle( self->curlm, easy );
			/* XXX: decrease refcount */
			XPUSHs( sv_2mortal( peasy->perl_self ) );
			peasy->perl_self = NULL;
			peasy->multi = NULL;
			XPUSHs( sv_2mortal( newSViv( res ) ) );
		} else {
			XSRETURN_EMPTY;
		}
		/* }}} */


void
curl_multi_fdset(self)
	WWW::CurlOO::Multi self
	PREINIT:
		fd_set fdread, fdwrite, fdexcep;
		int maxfd, i, vecsize;
		unsigned char readset[ sizeof( fd_set ) ] = { 0 };
		unsigned char writeset[ sizeof( fd_set ) ] = { 0 };
		unsigned char excepset[ sizeof( fd_set ) ] = { 0 };
	PPCODE:
		/* {{{ */
		FD_ZERO(&fdread);
		FD_ZERO(&fdwrite);
		FD_ZERO(&fdexcep);

		curl_multi_fdset(self->curlm, &fdread, &fdwrite, &fdexcep, &maxfd);
		vecsize = ( maxfd + 8 ) / 8;

		if ( maxfd != -1 ) {
			for (i=0;i <= maxfd;i++) {
				if (FD_ISSET(i, &fdread)) {
					readset[ i / 8 ] |= 1 << ( i % 8 );
				}
				if (FD_ISSET(i, &fdwrite)) {
					writeset[ i / 8 ] |= 1 << ( i % 8 );
				}
				if (FD_ISSET(i, &fdexcep)) {
					excepset[ i / 8 ] |= 1 << ( i % 8 );
				}
			}
		}
		XPUSHs( sv_2mortal( newSVpvn( (char *)readset, vecsize ) ) );
		XPUSHs( sv_2mortal( newSVpvn( (char *)writeset, vecsize ) ) );
		XPUSHs( sv_2mortal( newSVpvn( (char *)excepset, vecsize ) ) );
		/* }}} */


long
curl_multi_timeout(self)
	WWW::CurlOO::Multi self
	PREINIT:
		long timeout;
		CURLMcode ret;
	CODE:
		ret = curl_multi_timeout( self->curlm, &timeout );
		if ( ret != CURLM_OK )
			croak( "curl_multi_timeout() failed: %d\n", ret );

		RETVAL = timeout;
	OUTPUT:
		RETVAL

int
curl_multi_setopt(self, option, value)
	WWW::CurlOO::Multi self
	int option
	SV *value
	CODE:
		/* {{{ */
		RETVAL = CURLM_OK;
		switch( option ) {
			case CURLMOPT_SOCKETFUNCTION:
			case CURLMOPT_SOCKETDATA:
				curl_multi_setopt( self->curlm, CURLMOPT_SOCKETFUNCTION, SvOK(value) ? cb_multi_socket : NULL );
				curl_multi_setopt( self->curlm, CURLMOPT_SOCKETDATA, SvOK(value) ? self : NULL );
				perl_curl_multi_register_callback( aTHX_ self,
					option == CURLMOPT_SOCKETDATA ?
						&(self->cb[CB_MULTI_SOCKET].data) :
						&(self->cb[CB_MULTI_SOCKET].func),
					value);
				break;
			case CURLMOPT_TIMERFUNCTION:
			case CURLMOPT_TIMERDATA:
				curl_multi_setopt( self->curlm, CURLMOPT_TIMERFUNCTION, SvOK(value) ? cb_multi_timer : NULL );
				curl_multi_setopt( self->curlm, CURLMOPT_TIMERDATA, SvOK(value) ? self : NULL );
				perl_curl_multi_register_callback( aTHX_ self,
					option == CURLMOPT_TIMERDATA ?
						&(self->cb[CB_MULTI_TIMER].data) :
						&(self->cb[CB_MULTI_TIMER].func),
					value );
				break;

			/* default cases */
			default:
				if ( option < CURLOPTTYPE_OBJECTPOINT ) { /* A long (integer) value */
					RETVAL = curl_multi_setopt( self->curlm, option, (long)SvIV(value) );
				} else {
					croak( "Unknown curl multi option" );
				}
				break;
		};
		/* }}} */
	OUTPUT:
		RETVAL


int
curl_multi_perform(self)
	WWW::CurlOO::Multi self
	PREINIT:
		int remaining;
	CODE:
		self->perl_self = ST(0);
		while(CURLM_CALL_MULTI_PERFORM ==
			curl_multi_perform(self->curlm, &remaining));
		RETVAL = remaining;
	OUTPUT:
		RETVAL

int
curl_multi_socket_action(self, sockfd=CURL_SOCKET_BAD, ev_bitmask=0)
	WWW::CurlOO::Multi self
	int sockfd
	int ev_bitmask
	PREINIT:
		int remaining;
	CODE:
		self->perl_self = ST(0);
		while( CURLM_CALL_MULTI_PERFORM == curl_multi_socket_action(
				self->curlm, (curl_socket_t) sockfd, ev_bitmask, &remaining ) )
			;
		RETVAL = remaining;
	OUTPUT:
		RETVAL


void
curl_multi_DESTROY(self)
	WWW::CurlOO::Multi self
	CODE:
		perl_curl_multi_delete( aTHX_ self );

SV *
curl_multi_strerror( self, errornum )
	WWW::CurlOO::Multi self
	int errornum
	PREINIT:
		const char *errstr;
		(void) self; /* unused */
	CODE:
		errstr = curl_multi_strerror( errornum );
		RETVAL = newSVpv( errstr, 0 );
	OUTPUT:
		RETVAL

#endif
