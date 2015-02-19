/* vim: ts=4:sw=4:ft=xs:fdm=marker
 *
 * Copyright 2011-2015 (C) Przemyslaw Iskra <sparky at pld-linux.org>
 *
 * Loosely based on code by Cris Bailiff <c.bailiff+curl at devsecure.com>,
 * and subsequent fixes by other contributors.
 */


static size_t
write_to_ctx( pTHX_ SV* const call_ctx, const char* const ptr, size_t const n )
{
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
}


/* WRITEFUNCTION -- WRITEDATA */
static size_t
cb_easy_write( char *buffer, size_t size, size_t nitems, void *userptr )
{
	dTHX;
	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	callback_t *cb = &easy->cb[ CB_EASY_WRITE ];

	if ( cb->func ) {
		SV *args[] = {
			SELF2PERL( easy ),
			&PL_sv_undef
		};
		if ( buffer )
			args[1] = newSVpvn( buffer, (STRLEN) (size * nitems) );

		return PERL_CURL_CALL( cb, args );
	} else {
		return write_to_ctx( aTHX_ cb->data, buffer, size * nitems );
	}
}


/* HEADERFUNCTION -- WRITEHEADER */
static size_t
cb_easy_header( const void *ptr, size_t size, size_t nmemb,
		void *userptr )
{
	dTHX;
	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	callback_t *cb = &easy->cb[ CB_EASY_HEADER ];

	if ( cb->func ) {
		SV *args[] = {
			SELF2PERL( easy ),
			&PL_sv_undef
		};
		if ( ptr )
			args[1] = newSVpvn( ptr, (STRLEN) (size * nmemb) );

		return PERL_CURL_CALL( cb, args );
	} else {
		return write_to_ctx( aTHX_ cb->data, ptr, size * nmemb );
	}
}


/* DEBUGFUNCTION -- DEBUGDATA */
static int
cb_easy_debug( CURL *easy_handle, curl_infotype type, char *ptr, size_t size,
		void *userptr )
{
	dTHX;
	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	callback_t *cb = &easy->cb[ CB_EASY_DEBUG ];

	if ( cb->func ) {
		/* We are doing a callback to perl */
		SV *args[] = {
			SELF2PERL( easy ),
			newSViv( type ),
			&PL_sv_undef
		};
		if ( ptr )
			args[2] = newSVpvn( ptr, (STRLEN) (size) );

		return PERL_CURL_CALL( cb, args );
	} else {
		return write_to_ctx( aTHX_ cb->data, ptr, size );
	}

}


/* READFUNCTION -- READDATA */
static size_t
cb_easy_read( char *ptr, size_t size, size_t nmemb, void *userptr )
{
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
		int method_call = 0;

		if ( SvROK( cb->func ) )
			method_call = 0;
		else if ( SvPOK( cb->func ) )
			method_call = 1;
		else {
			warn( "Don't know how to call the callback\n" );
			return CURL_READFUNC_ABORT;
		}

		ENTER;
		SAVETMPS;

		PUSHMARK( SP );

		/* $easy, $maxsize, $userdata */
		EXTEND( SP, 2 );
		mPUSHs( SELF2PERL( easy ) ),
		mPUSHs( newSViv( maxlen ) );
		if ( cb->data )
			mXPUSHs( newSVsv( cb->data ) );

		PUTBACK;

		if ( SvTRUE( ERRSV ) )
			olderrsv = sv_2mortal( newSVsv( ERRSV ) );

		if ( method_call )
			call_method( SvPV_nolen( cb->func ), G_SCALAR | G_EVAL );
		else
			call_sv( cb->func, G_SCALAR | G_EVAL );

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
}


/* PROGRESSFUNCTION -- PROGRESSDATA */
static int
cb_easy_progress( void *userptr, double dltotal, double dlnow,
		double ultotal, double ulnow )
{
	dTHX;

	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	callback_t *cb = &easy->cb[ CB_EASY_PROGRESS ];

	SV *args[] = {
		SELF2PERL( easy ),
		newSVnv( dltotal ),
		newSVnv( dlnow ),
		newSVnv( ultotal ),
		newSVnv( ulnow )
	};

	return PERL_CURL_CALL( cb, args );
}


#ifdef CURLOPT_XFERINFOFUNCTION
/* XFERINFOFUNCTION -- XFERINFODATA */
static int
cb_easy_xferinfo( void *userptr, curl_off_t dltotal, curl_off_t dlnow,
		curl_off_t ultotal, curl_off_t ulnow )
{
	dTHX;

	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	callback_t *cb = &easy->cb[ CB_EASY_XFERINFO ];

	SV *args[] = {
		SELF2PERL( easy ),
		newSViv( dltotal ),
		newSViv( dlnow ),
		newSViv( ultotal ),
		newSViv( ulnow )
	};

	return PERL_CURL_CALL( cb, args );
}
#endif


/* IOCTLFUNCTION -- IOCTLDATA */
static curlioerr
cb_easy_ioctl( CURL *easy_handle, int cmd, void *userptr )
{
	dTHX;

	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	callback_t *cb = &easy->cb[ CB_EASY_IOCTL ];

	SV *args[] = {
		SELF2PERL( easy ),
		newSViv( cmd ),
	};

	return PERL_CURL_CALL( cb, args );
}


#ifdef CURLOPT_SEEKFUNCTION
/* SEEKFUNCTION -- SEEKDATA */
static int
cb_easy_seek( void *userptr, curl_off_t offset, int origin )
{
	dTHX;

	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	callback_t *cb = &easy->cb[ CB_EASY_SEEK ];

	SV *args[] = {
		SELF2PERL( easy ),
		newSViv( offset ),
		newSViv( origin ),
	};

	return PERL_CURL_CALL( cb, args );
}
#endif


#ifdef CURLOPT_SOCKOPTFUNCTION
/* SOCKOPTFUNCTION -- SOCKOPTDATA */
static int
cb_easy_sockopt( void *userptr, curl_socket_t curlfd, curlsocktype purpose )
{
	dTHX;

	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	callback_t *cb = &easy->cb[ CB_EASY_SOCKOPT ];

	SV *args[] = {
		SELF2PERL( easy ),
		newSViv( curlfd ),
		newSViv( purpose ),
	};

	return PERL_CURL_CALL( cb, args );
}
#endif


#ifdef CURLOPT_OPENSOCKETFUNCTION
/* OPENSOCKETFUNCTION -- OPENSOCKETDATA */
static curl_socket_t
cb_easy_opensocket( void *userptr, curlsocktype purpose,
	struct curl_sockaddr *address )
{
	dTHX;

	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	callback_t *cb = &easy->cb[ CB_EASY_OPENSOCKET ];
	curl_socket_t ret;
	HV *ah = NULL;

	SV *args[] = {
		SELF2PERL( easy ),
		newSViv( purpose ),
		&PL_sv_undef,
	};
	if ( address ) {
		ah = newHV();
		(void) hv_stores( ah, "family", newSViv( address->family ) );
		(void) hv_stores( ah, "socktype", newSViv( address->socktype ) );
		(void) hv_stores( ah, "protocol", newSViv( address->protocol ) );
		(void) hv_stores( ah, "addr", newSVpvn( (const char *) &address->addr,
			address->addrlen ) );
		args[2] = newRV( sv_2mortal( (SV *) ah ) );
	}

	ret = PERL_CURL_CALL( cb, args );

	if ( address ) {
		SV **tmp;

		tmp = hv_fetchs( ah, "family", 0 );
		if ( tmp && *tmp && SvOK( *tmp ) )
			address->family = SvIV( *tmp );

		tmp = hv_fetchs( ah, "socktype", 0 );
		if ( tmp && *tmp && SvOK( *tmp ) )
			address->socktype = SvIV( *tmp );

		tmp = hv_fetchs( ah, "protocol", 0 );
		if ( tmp && *tmp && SvOK( *tmp ) )
			address->protocol = SvIV( *tmp );

		tmp = hv_fetchs( ah, "addr", 0 );
		if ( tmp && *tmp && SvOK( *tmp ) ) {
			STRLEN len;
			char *source = SvPV( *tmp, len );
			if ( len > sizeof( struct sockaddr_storage ) )
				len = sizeof( struct sockaddr_storage );
			Copy( source, (char *) &address->addr, len, char );
			address->addrlen = len;
		}
	}

	return ret;
}
#endif


#ifdef CURLOPT_CLOSESOCKETFUNCTION
/* CLOSESOCKETFUNCTION -- CLOSESOCKETDATA */
static void
cb_easy_closesocket( void *userptr, curl_socket_t item )
{
	dTHX;

	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	callback_t *cb = &easy->cb[ CB_EASY_CLOSESOCKET ];

	SV *args[] = {
		SELF2PERL( easy ),
		newSViv( item ),
	};

	PERL_CURL_CALL( cb, args );

	return;
}
#endif


#ifdef CURLOPT_INTERLEAVEFUNCTION
/* INTERLEAVEFUNCTION -- INTERLEAVEDATA */
static size_t
cb_easy_interleave( void *ptr, size_t size, size_t nmemb, void *userptr )
{
	dTHX;
	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	callback_t *cb = &easy->cb[ CB_EASY_INTERLEAVE ];

	if ( cb->func ) {
		SV *args[] = {
			SELF2PERL( easy ),
			&PL_sv_undef
		};
		if ( ptr )
			args[1] = newSVpvn( ptr, (STRLEN) (size * nmemb) );

		return PERL_CURL_CALL( cb, args );
	} else {
		return write_to_ctx( aTHX_ cb->data, ptr, size * nmemb );
	}
}
#endif


#ifdef CURL_CHUNK_BGN_FUNC_FAIL
/* CHUNK_BGN_FUNCTION -- CHUNK_DATA */
static long
cb_easy_chunk_bgn( const void *transfer_info, void *userptr, int remains )
{
	dTHX;
	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	callback_t *cb = &easy->cb[ CB_EASY_CHUNK_BGN ];

	SV *args[] = {
		SELF2PERL( easy ),
		&PL_sv_undef,
		newSViv( remains )
	};
	if ( transfer_info ) {
		const struct curl_fileinfo *fi = transfer_info;
		HV *h, *s;

		s = newHV();
		if ( fi->strings.time )
			(void) hv_stores( s, "time", newSVpv( fi->strings.time, 0 ) );
		if ( fi->strings.perm )
			(void) hv_stores( s, "perm", newSVpv( fi->strings.perm, 0 ) );
		if ( fi->strings.user )
			(void) hv_stores( s, "user", newSVpv( fi->strings.user, 0 ) );
		if ( fi->strings.group )
			(void) hv_stores( s, "group", newSVpv( fi->strings.group, 0 ) );
		if ( fi->strings.target )
			(void) hv_stores( s, "target", newSVpv( fi->strings.target, 0 ) );

		h = newHV();
		if ( fi->filename
# ifdef CURLFINFOFLAG_KNOWN_FILENAME
				&& ( fi->flags & CURLFINFOFLAG_KNOWN_FILENAME )
# endif
			)
			(void) hv_stores( h, "filename", newSVpv( fi->filename, 0 ) );
# ifdef CURLFINFOFLAG_KNOWN_FILETYPE
		if ( fi->flags & CURLFINFOFLAG_KNOWN_FILETYPE )
# endif
			(void) hv_stores( h, "filetype", newSViv( fi->filetype ) );
# ifdef CURLFINFOFLAG_KNOWN_TIME
		if ( fi->flags & CURLFINFOFLAG_KNOWN_TIME )
# endif
			(void) hv_stores( h, "time", newSViv( fi->time ) );
# ifdef CURLFINFOFLAG_KNOWN_PERM
		if ( fi->flags & CURLFINFOFLAG_KNOWN_PERM )
# endif
			(void) hv_stores( h, "perm", newSVuv( fi->perm ) );
# ifdef CURLFINFOFLAG_KNOWN_UID
		if ( fi->flags & CURLFINFOFLAG_KNOWN_UID )
# endif
			(void) hv_stores( h, "uid", newSViv( fi->uid ) );
# ifdef CURLFINFOFLAG_KNOWN_GID
		if ( fi->flags & CURLFINFOFLAG_KNOWN_GID )
# endif
			(void) hv_stores( h, "gid", newSViv( fi->gid ) );
# ifdef CURLFINFOFLAG_KNOWN_SIZE
		if ( fi->flags & CURLFINFOFLAG_KNOWN_SIZE )
# endif
			(void) hv_stores( h, "size", newSV( fi->size ) );
# ifdef CURLFINFOFLAG_KNOWN_HLINKCOUNT
		if ( fi->flags & CURLFINFOFLAG_KNOWN_HLINKCOUNT )
# endif
			(void) hv_stores( h, "hardlinks", newSViv( fi->hardlinks ) );
		(void) hv_stores( h, "strings", newRV( sv_2mortal( (SV *) s ) ) );
		(void) hv_stores( h, "flags", newSVuv( fi->flags ) );

		args[2] = newRV( sv_2mortal( (SV *) h ) );
	}

	return PERL_CURL_CALL( cb, args );
}
#endif


#ifdef CURL_CHUNK_END_FUNC_FAIL
/* CHUNK_END_FUNCTION -- CHUNK_DATA */
static long
cb_easy_chunk_end( void *userptr )
{
	dTHX;

	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	callback_t *cb = &easy->cb[ CB_EASY_CHUNK_END ];

	SV *args[] = {
		SELF2PERL( easy ),
	};

	return PERL_CURL_CALL( cb, args );
}
#endif


#ifdef CURL_FNMATCHFUNC_FAIL
/* FNMATCH_FUNCTION -- FNMATCH_DATA */
static int
cb_easy_fnmatch( void *userptr, const char *pattern, const char *string )
{
	dTHX;

	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	callback_t *cb = &easy->cb[ CB_EASY_FNMATCH ];

	SV *args[] = {
		SELF2PERL( easy ),
		newSVpv( pattern, 0 ),
		newSVpv( string, 0 ),
	};

	return PERL_CURL_CALL( cb, args );
}
#endif


#ifdef CURLKHMATCH_OK
/* SSH_KEYFUNCTION -- SSH_KEYDATA */
static SV *
perl_curl_khkey2hash( pTHX_ const struct curl_khkey *key )
{
	HV *h;

	if ( !key )
		return &PL_sv_undef;

	h = newHV();
	(void) hv_stores( h, "key", newSVpv( key->key, key->len ) );
	(void) hv_stores( h, "len", newSVuv( key->len ) );
	(void) hv_stores( h, "keytype", newSViv( key->keytype ) );

	return newRV( sv_2mortal( (SV *) h ) );
}

static int
cb_easy_sshkey( CURL *easy_handle, const struct curl_khkey *knownkey,
	const struct curl_khkey *foundkey, enum curl_khmatch khmatch,
	void *userptr )
{
	dTHX;

	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	callback_t *cb = &easy->cb[ CB_EASY_SSHKEY ];

	SV *args[] = {
		SELF2PERL( easy ),
		perl_curl_khkey2hash( aTHX_ knownkey ),
		perl_curl_khkey2hash( aTHX_ foundkey ),
		newSViv( khmatch ),
	};

	return PERL_CURL_CALL( cb, args );
}
#endif


#ifdef CALLBACK_TYPECHECK
static curl_progress_callback t_progress __attribute__((unused)) = cb_easy_progress;
#ifdef CURLOPT_XFERINFOFUNCTION
static curl_xferinfo_callback t_xferinfo __attribute__((unused)) = cb_easy_xferinfo;
#endif
static curl_write_callback t_write __attribute__((unused)) = cb_easy_write;
static curl_chunk_bgn_callback t_chunk_bgn __attribute__((unused)) = cb_easy_chunk_bgn;
static curl_chunk_end_callback t_chunk_end __attribute__((unused)) = cb_easy_chunk_end;
static curl_fnmatch_callback t_fnmatch __attribute__((unused)) = cb_easy_fnmatch;
static curl_seek_callback t_seek __attribute__((unused)) = cb_easy_seek;
static curl_read_callback t_read __attribute__((unused)) = cb_easy_read;
static curl_sockopt_callback t_sockopt __attribute__((unused)) = cb_easy_sockopt;
static curl_opensocket_callback t_opensocket __attribute__((unused)) = cb_easy_opensocket;
/*static curl_closesocket_callback t_closesocket __attribute__((unused)) = cb_easy_closesocket;*/
static curl_ioctl_callback t_ioctl __attribute__((unused)) = cb_easy_ioctl;
static curl_debug_callback t_debug __attribute__((unused)) = cb_easy_debug;
static curl_sshkeycallback t_sshkey __attribute__((unused)) = cb_easy_sshkey;
#endif
