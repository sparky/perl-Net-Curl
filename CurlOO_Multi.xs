MODULE = WWW::CurlOO	PACKAGE = WWW::CurlOO::Multi	PREFIX = curl_multi_

INCLUDE: const-multi-xs.inc

void
curl_multi_new( ... )
	PREINIT:
		perl_curl_multi_t *self;
		char *sclass = "WWW::CurlOO::Multi";
		SV *base;
		HV *stash;
	PPCODE:
		if ( items > 0 && !SvROK( ST(0) )) {
			STRLEN dummy;
			sclass = SvPV( ST(0), dummy );
		}
		if ( items > 1 ) {
			base = ST(1);
			if ( ! SvOK( base ) || ! SvROK( base ) )
				croak( "object base must be a valid reference\n" );
		} else
			base = newRV_noinc( (SV *)newHV() );

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
		curl_multi_add_handle(curlm->curlm, curl->curl);

void
curl_multi_remove_handle(curlm, curl)
	WWW::CurlOO::Multi curlm
	WWW::CurlOO::Easy curl
	CODE:
		curl_multi_remove_handle(curlm->curlm, curl->curl);

void
curl_multi_info_read(self)
	WWW::CurlOO::Multi self
	PREINIT:
		CURL *easy = NULL;
		CURLcode res;
		char *stashid;
		int queue;
		CURLMsg *msg;
	PPCODE:
		/* {{{ */
		while ((msg = curl_multi_info_read(self->curlm, &queue))) {
			if (msg->msg == CURLMSG_DONE) {
					easy=msg->easy_handle;
					res=msg->data.result;
			break;
			}
		};
		if (easy) {
			curl_easy_getinfo(easy, CURLINFO_PRIVATE, &stashid);
			curl_multi_remove_handle(self->curlm, easy);
			XPUSHs(sv_2mortal(newSVpv(stashid,0)));
			XPUSHs(sv_2mortal(newSViv(res)));
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
		XPUSHs(sv_2mortal(newSVpvn(readset, vecsize)));
		XPUSHs(sv_2mortal(newSVpvn(writeset, vecsize)));
		XPUSHs(sv_2mortal(newSVpvn(excepset, vecsize)));
		/* }}} */


long
curl_multi_timeout(self)
	WWW::CurlOO::Multi self
	PREINIT:
		long timeout;
		CURLMcode ret;
	CODE:
		if ( curl_multi_timeout( self->curlm, &timeout ) != CURLM_OK )
			croak( "curl_multi_timeout() didn't return CURLM_OK" );

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
					option == CURLMOPT_SOCKETDATA ? &(self->callback_ctx[CALLBACKM_SOCKET]) : &(self->callback[CALLBACKM_SOCKET]),
					value);
				break;
			case CURLMOPT_TIMERFUNCTION:
			case CURLMOPT_TIMERDATA:
				curl_multi_setopt( self->curlm, CURLMOPT_TIMERFUNCTION, SvOK(value) ? cb_multi_timer : NULL );
				curl_multi_setopt( self->curlm, CURLMOPT_TIMERDATA, SvOK(value) ? self : NULL );
				perl_curl_multi_register_callback( aTHX_ self,
					option == CURLMOPT_TIMERDATA ? &(self->callback_ctx[CALLBACKM_TIMER]) : &(self->callback[CALLBACKM_TIMER]),
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
	CODE:
		errstr = curl_multi_strerror( errornum );
		RETVAL = newSVpv( errstr, 0 );
	OUTPUT:
		RETVAL
