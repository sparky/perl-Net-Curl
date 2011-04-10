/* vim: ts=4:sw=4:ft=xs:fdm=marker: */
/*
 * Copyright 2011 (C) Przemyslaw Iskra <sparky at pld-linux.org>
 *
 * Loosely based on code by Cris Bailiff <c.bailiff+curl at devsecure.com>,
 * and subsequent fixes by other contributors.
 */


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

/* IOCTLFUNCTION -- IOCTLDATA */
static curlioerr
cb_easy_ioctl( CURL *handle, int cmd, void *userptr )
{
	dTHX;

	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	callback_t *cb = &easy->cb[ CB_EASY_IOCTL ];

	SV *args[] = {
		newSVsv( easy->perl_self ),
		newSViv( cmd ),
	};

	return PERL_CURL_CALL( cb, args );
}


# ifdef CURLOPT_SEEKFUNCTION
/* SEEKFUNCTION -- SEEKDATA */
static int
cb_easy_seek( void *userptr, curl_off_t offset, int origin )
{
	dTHX;

	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	callback_t *cb = &easy->cb[ CB_EASY_SEEK ];

	SV *args[] = {
		newSVsv( easy->perl_self ),
		newSViv( offset ),
		newSViv( origin ),
	};

	return PERL_CURL_CALL( cb, args );
}
#endif


# ifdef CURLOPT_SOCKOPTFUNCTION
/* SOCKOPTFUNCTION -- SOCKOPTDATA */
static int
cb_easy_sockopt( void *userptr, curl_socket_t curlfd, curlsocktype purpose )
{
	dTHX;

	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	callback_t *cb = &easy->cb[ CB_EASY_SOCKOPT ];

	SV *args[] = {
		newSVsv( easy->perl_self ),
		newSViv( curlfd ),
		newSViv( purpose ),
	};

	return ( PERL_CURL_CALL( cb, args ) ? 1 : 0 );
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


	SV *args[] = {
		newSVsv( easy->perl_self ),
		newSViv( purpose ),
		&PL_sv_undef,
	};
	if ( address ) {
		HV *ah;
		ah = newHV();
		(void) hv_stores( ah, "family", newSViv( address->family ) );
		(void) hv_stores( ah, "socktype", newSViv( address->socktype ) );
		(void) hv_stores( ah, "protocol", newSViv( address->protocol ) );
		(void) hv_stores( ah, "addrlen", newSVuv( address->addrlen ) );
		/* XXX: is this correct ? */
		(void) hv_stores( ah, "addr", newSVpvn( (const char *) &address->addr,
			sizeof( struct sockaddr ) ) );
		args[2] = newRV( sv_2mortal( (SV *) ah ) );
	}

	return PERL_CURL_CALL( cb, args );
}
#endif


#ifdef CURLOPT_INTERLEAVEFUNCTION
/* INTERLEAVEFUNCTION -- INTERLEAVEDATA */
static size_t
cb_easy_interleave( void *ptr, size_t size, size_t nmemb, void *userptr )
{
	/*
    Function  pointer that should match the following prototype: size_t
    function( void *ptr, size_t size, size_t  nmemb,  void  *userdata).
    This  function  gets  called  by libcurl as soon as it has received
    interleaved RTP data. This function gets called for  each  $  block
    and  therefore contains exactly one upper-layer protocol unit (e.g.
    one RTP packet). Curl writes the interleaved header as well as  the
    included data for each call. The first byte is always an ASCII dol-
    lar sign. The dollar sign is followed by a one byte channel identi-
    fier  and  then  a 2 byte integer length in network byte order. See
    RFC 2326 Section 10.12 for more information on how RTP interleaving
    behaves.  If  unset or set to NULL, curl will use the default write
    function.

    Interleaved RTP poses some challeneges for the client  application.
    Since the stream data is sharing the RTSP control connection, it is
    critical to service the RTP in a timely fashion. If the RTP data is
    not  handled  quickly,  subsequent  response  processing may become
    unreasonably delayed and the connection may close. The  application
    may  use  CURL/RTSPREQ_RECEIVE to service RTP data when no requests
    are  desired.  If  the   application   makes   a   request,   (e.g.
    CURL/RTSPREQ_PAUSE)  then  the  response  handler  will process any
    pending RTP data before marking the request as finished.  (Added in
    7.20.0)
	*/

	return -1;
}
#endif


#ifdef CURL_CHUNK_BGN_FUNC_FAIL
/* CHUNK_BGN_FUNCTION -- CHUNK_DATA */
static long
cb_easy_chunk_bgn( const void *transfer_info, void *ptr, int remains )
{
	/*
    Function  pointer  that  should match the following prototype: long
    function (const void *transfer_info, void *ptr, int remains).  This
    function  gets  called  by  libcurl  before a part of the stream is
    going to be transferred (if the transfer supports chunks).

    This callback makes sense only when using the CURLOPT/WILDCARDMATCH
    option for now.

    The  target  of  transfer_info  parameter  is  a "feature depended"
    structure. For the FTP wildcard download, the target is  curl_file-
    info  structure  (see curl/curl.h).  The parameter ptr is a pointer
    given by CURLOPT/CHUNK_DATA. The parameter remains contains  number
    of  chunks remaining per the transfer. If the feature is not avail-
    able, the parameter has zero value.

    Return    CURL/CHUNK_BGN_FUNC_OK    if    everything    is    fine,
    CURL/CHUNK_BGN_FUNC_SKIP  if you want to skip the concrete chunk or
    CURL/CHUNK_BGN_FUNC_FAIL to tell libcurl  to  stop  if  some  error
    occurred.  (This was added in 7.21.0)
	*/

	return CURL_CHUNK_BGN_FUNC_FAIL;
}
#endif


#ifdef CURL_CHUNK_END_FUNC_FAIL
/* CHUNK_END_FUNCTION -- CHUNK_DATA */
static long
cb_easy_chunk_end( void *userptr )
{
	dTHX;
	long ret;

	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	callback_t *cb = &easy->cb[ CB_EASY_CHUNK_END ];

	SV *args[] = {
		newSVsv( easy->perl_self ),
	};

	ret = PERL_CURL_CALL( cb, args );
	if ( 0
# ifdef CURL_CHUNK_END_FUNC_OK
			|| ret == CURL_CHUNK_END_FUNC_OK
# endif
		)
		return ret;
	return CURL_CHUNK_END_FUNC_FAIL;
}
#endif


#ifdef CURL_FNMATCHFUNC_FAIL
/* FNMATCH_FUNCTION -- FNMATCH_DATA */
static int
cb_easy_fnmatch( void *userptr, const char *pattern, const char *string )
{
	dTHX;
	long ret;

	perl_curl_easy_t *easy;
	easy = (perl_curl_easy_t *) userptr;
	callback_t *cb = &easy->cb[ CB_EASY_FNMATCH ];

	SV *args[] = {
		newSVsv( easy->perl_self ),
		newSVpv( pattern, 0 ),
		newSVpv( string, 0 ),
	};

	ret = PERL_CURL_CALL( cb, args );
	if ( 0
# ifdef CURL_FNMATCHFUNC_MATCH
			|| ret == CURL_FNMATCHFUNC_MATCH
# endif
# ifdef CURL_FNMATCHFUNC_NOMATCH
			|| ret == CURL_FNMATCHFUNC_NOMATCH
# endif
		)
		return ret;
	return CURL_FNMATCHFUNC_FAIL;
}
#endif
