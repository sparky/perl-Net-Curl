/* vim: ts=4:sw=4:ft=xs:fdm=marker: */
/*
 * Copyright 2011 (C) Przemyslaw Iskra <sparky at pld-linux.org>
 *
 * Loosely based on code by Cris Bailiff <c.bailiff+curl at devsecure.com>,
 * and subsequent fixes by other contributors.
 */


static void
perl_curl_easy_setopt_long( pTHX_ perl_curl_easy_t *easy, long option,
		SV *value )
{
	CURLcode ret = CURLE_OK;
	long value_num = 0;
	if ( SvOK( value ) )
		value_num = (long) SvIV( value );

	ret = curl_easy_setopt( easy->handle, option, value_num );
	EASY_DIE( ret );
}


static void
perl_curl_easy_setopt_function( pTHX_ perl_curl_easy_t *easy, long option,
		SV *value )
{
	int cbnum = CB_EASY_LAST;
	int dataopt = 0;
	void *funcptr = NULL;

	switch ( option ) {
		case CURLOPT_WRITEFUNCTION:
			/* function registered already */
			cbnum = CB_EASY_WRITE;
			break;
		case CURLOPT_READFUNCTION:
			/* function registered already */
			cbnum = CB_EASY_READ;
			break;
		case CURLOPT_HEADERFUNCTION:
			funcptr = cb_easy_header;
			dataopt = CURLOPT_WRITEHEADER;
			cbnum = CB_EASY_HEADER;
			break;
		case CURLOPT_PROGRESSFUNCTION:
			funcptr = cb_easy_progress;
			dataopt = CURLOPT_PROGRESSDATA;
			cbnum = CB_EASY_PROGRESS;
			break;
		case CURLOPT_DEBUGFUNCTION:
			funcptr = cb_easy_debug;
			dataopt = CURLOPT_DEBUGDATA;
			cbnum = CB_EASY_DEBUG;
			break;
		case CURLOPT_IOCTLFUNCTION:
			funcptr = cb_easy_ioctl;
			dataopt = CURLOPT_IOCTLDATA;
			cbnum = CB_EASY_IOCTL;
			break;
#ifdef CURLOPT_SEEKDATA
# ifdef CURLOPT_SEEKFUNCTION
		case CURLOPT_SEEKFUNCTION:
			funcptr = cb_easy_seek;
			dataopt = CURLOPT_SEEKDATA;
			cbnum = CB_EASY_SEEK;
			break;
# endif
#endif
#ifdef CURLOPT_SOCKOPTDATA
# ifdef CURLOPT_SOCKOPTFUNCTION
		case CURLOPT_SOCKOPTFUNCTION:
			funcptr = cb_easy_sockopt;
			dataopt = CURLOPT_SOCKOPTDATA;
			cbnum = CB_EASY_SOCKOPT;
			break;
# endif
#endif
#ifdef CURLOPT_OPENSOCKETDATA
# ifdef CURLOPT_OPENSOCKETFUNCTION
		case CURLOPT_OPENSOCKETFUNCTION:
			funcptr = cb_easy_opensocket;
			dataopt = CURLOPT_OPENSOCKETDATA;
			cbnum = CB_EASY_OPENSOCKET;
			break;
# endif
#endif
#ifdef CURLOPT_CLOSESOCKETDATA
# ifdef CURLOPT_CLOSESOCKETFUNCTION
		case CURLOPT_CLOSESOCKETFUNCTION:
			funcptr = cb_easy_closesocket;
			dataopt = CURLOPT_CLOSESOCKETDATA;
			cbnum = CB_EASY_CLOSESOCKET;
			break;
# endif
#endif
#ifdef CURLOPT_INTERLEAVEDATA
# ifdef CURLOPT_INTERLEAVEFUNCTION
		case CURLOPT_INTERLEAVEFUNCTION:
			funcptr = cb_easy_interleave;
			dataopt = CURLOPT_INTERLEAVEDATA;
			cbnum = CB_EASY_INTERLEAVE;
			break;
# endif
#endif
#ifdef CURLOPT_CHUNK_DATA
# ifdef CURLOPT_CHUNK_BGN_FUNCTION
		case CURLOPT_CHUNK_BGN_FUNCTION:
			funcptr = cb_easy_chunk_bgn;
			dataopt = CURLOPT_CHUNK_DATA;
			cbnum = CB_EASY_CHUNK_BGN;
			break;
# endif
# ifdef CURLOPT_CHUNK_END_FUNCTION
		case CURLOPT_CHUNK_END_FUNCTION:
			funcptr = cb_easy_chunk_end;
			dataopt = CURLOPT_CHUNK_DATA;
			cbnum = CB_EASY_CHUNK_END;
			break;
# endif
#endif
#ifdef CURLOPT_FNMATCH_DATA
# ifdef CURLOPT_FNMATCH_FUNCTION
		case CURLOPT_FNMATCH_FUNCTION:
			funcptr = cb_easy_fnmatch;
			dataopt = CURLOPT_FNMATCH_DATA;
			cbnum = CB_EASY_FNMATCH;
			break;
# endif
#endif
#ifdef CURLOPT_SSH_KEYDATA
# ifdef CURLOPT_SSH_KEYFUNCTION
		case CURLOPT_SSH_KEYFUNCTION:
			funcptr = cb_easy_sshkey;
			dataopt = CURLOPT_SSH_KEYDATA;
			cbnum = CB_EASY_SSHKEY;
			break;
# endif
#endif
		default:
			croak( "unrecognized function option %ld", option );
	}

	if ( cbnum != CB_EASY_LAST )
		SvREPLACE( easy->cb[ cbnum ].func, value );

	if ( dataopt ) {
		CURLcode ret1, ret2;
		ret1 = curl_easy_setopt( easy->handle, option,
			SvOK( value ) ? funcptr : NULL );
		ret2 = curl_easy_setopt( easy->handle, dataopt,
			SvOK( value ) ? easy : NULL );

		EASY_DIE( ret1 ? ret1 : ret2 );
	}
}

static long
perl_curl_easy_setopt_functiondata( pTHX_ perl_curl_easy_t *easy, long option,
		SV *value )
{
	int cbnum = CB_EASY_LAST;
	CURLcode ret = CURLE_OK;

	switch ( option ) {
		case CURLOPT_FILE:
			cbnum = CB_EASY_WRITE;
			break;
		case CURLOPT_INFILE:
			cbnum = CB_EASY_READ;
			break;
		case CURLOPT_WRITEHEADER:
			/* cb_easy_header has default writer function,
			 * but no default destination */
			{
				CURLcode ret2;
				ret = curl_easy_setopt( easy->handle, CURLOPT_HEADERFUNCTION,
					SvOK( value ) ? cb_easy_header : NULL );
				ret2 = curl_easy_setopt( easy->handle, option,
					SvOK( value ) ? easy : NULL );
				if ( ret == CURLE_OK )
					ret = ret2;
			}
			cbnum = CB_EASY_HEADER;
			break;
		case CURLOPT_PROGRESSDATA:
			cbnum = CB_EASY_PROGRESS;
			break;
		case CURLOPT_DEBUGDATA:
			cbnum = CB_EASY_DEBUG;
			break;

		case CURLOPT_IOCTLDATA:
			cbnum = CB_EASY_IOCTL;
			break;
#ifdef CURLOPT_SEEKDATA
		case CURLOPT_SEEKDATA:
			cbnum = CB_EASY_SEEK;
			break;
#endif
#ifdef CURLOPT_SOCKOPTDATA
		case CURLOPT_SOCKOPTDATA:
			cbnum = CB_EASY_SOCKOPT;
			break;
#endif
#ifdef CURLOPT_OPENSOCKETDATA
		case CURLOPT_OPENSOCKETDATA:
			cbnum = CB_EASY_OPENSOCKET;
			break;
#endif
#ifdef CURLOPT_CLOSESOCKETDATA
		case CURLOPT_CLOSESOCKETDATA:
			cbnum = CB_EASY_CLOSESOCKET;
			break;
#endif
#ifdef CURLOPT_INTERLEAVEDATA
		case CURLOPT_INTERLEAVEDATA:
# ifdef CURLOPT_INTERLEAVEFUNCTION
			/* cb_easy_interleave has default writer function,
			 * but no default destination */
			{
				CURLcode ret2;
				ret = curl_easy_setopt( easy->handle, CURLOPT_INTERLEAVEFUNCTION,
					SvOK( value ) ? cb_easy_interleave : NULL );
				ret2 = curl_easy_setopt( easy->handle, option,
					SvOK( value ) ? easy : NULL );
				if ( ret == CURLE_OK )
					ret = ret2;
			}
# endif
			cbnum = CB_EASY_INTERLEAVE;
			break;
#endif
#ifdef CURLOPT_CHUNK_DATA
		case CURLOPT_CHUNK_DATA:
			cbnum = CB_EASY_CHUNK_BGN;
			SvREPLACE( easy->cb[ cbnum ].data, value );
			cbnum = CB_EASY_CHUNK_END;
			break;
#endif
#ifdef CURLOPT_FNMATCH_DATA
		case CURLOPT_FNMATCH_DATA:
			cbnum = CB_EASY_FNMATCH;
			break;
#endif
#ifdef CURLOPT_SSH_KEYDATA
		case CURLOPT_SSH_KEYDATA:
			cbnum = CB_EASY_SSHKEY;
			break;
#endif

		default:
			return -1;
	}

	SvREPLACE( easy->cb[ cbnum ].data, value );

	return ret;
}

static void
perl_curl_easy_setopt_object( pTHX_ perl_curl_easy_t *easy, long option,
		SV *value )
{
	int ret = CURLE_OK;
	char *pv;

	/* is it a function data ? */
	ret = perl_curl_easy_setopt_functiondata( aTHX_ easy, option, value );
	if ( ret >= 0 ) {
		EASY_DIE( ret );
		return;
	}

	/* is it a slist option ? */
	ret = perl_curl_easy_setoptslist( aTHX_ easy, option, value, 1 );
	if ( ret >= 0 ) {
		EASY_DIE( ret );
		return;
	}

	switch ( option ) {
		case CURLOPT_ERRORBUFFER:
			croak( "CURLOPT_ERRORBUFFER is not supported, use $easy->error instead" );
			return;

		/* tell curl to redirect STDERR - value should be a glob */
		case CURLOPT_STDERR:
			ret = curl_easy_setopt( easy->handle, option,
				PerlIO_findFILE( IoOFP( sv_2io( value ) ) ) );
			return;

		case CURLOPT_HTTPPOST:
			if ( easy->form_sv ) {
				curl_easy_setopt( easy->handle, option, NULL );
				sv_2mortal( easy->form_sv );
				easy->form_sv = NULL;
			}

			if ( SvOK( value ) ) {
				perl_curl_form_t *form;
				form = perl_curl_getptr_fatal( aTHX_ value, &perl_curl_form_vtbl,
					"CURLOPT_HTTPPOST", "Net::Curl::Form" );

				easy->form_sv = newSVsv( value );
				ret = curl_easy_setopt( easy->handle, option, form->post );
				EASY_DIE( ret );
			}
			return;

		case CURLOPT_SHARE:
			if ( easy->share_sv ) {
				curl_easy_setopt( easy->handle, option, NULL );
				sv_2mortal( easy->share_sv );
				easy->share_sv = NULL;
			}

			if ( SvOK( value ) ) {
				perl_curl_share_t *share;
				share = perl_curl_getptr_fatal( aTHX_ value, &perl_curl_share_vtbl,
					"CURLOPT_SHARE", "Net::Curl::Share" );

				/* copy sv before setopt because this may trigger a callback */
				easy->share_sv = newSVsv( value );
				ret = curl_easy_setopt( easy->handle, option, share->handle );
				EASY_DIE( ret );
			}
			return;

		case CURLOPT_PRIVATE:
			croak( "CURLOPT_PRIVATE is not available, use your base object" );
			return;
	};

	/* default, assume it's data */
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

	ret = curl_easy_setopt( easy->handle, option, pv );
	EASY_DIE( ret );
}



static void
perl_curl_easy_setopt_off_t( pTHX_ perl_curl_easy_t *easy, long option,
		SV *value )
{
	CURLcode ret = CURLE_OK;
	/* this should be curl_off_t, but there is a bug in older curl - 7.18.2 */
	long long v = 0;

	if ( SvOK( value ) ) {
		if ( SvIOK( value ) ) {
			v = SvIV( value );
		} else if ( looks_like_number( value ) ) {
#if IVSIZE == 8
			v = SvIV( value );
#else
			char *pv = SvPV_nolen( value );
			char *pdummy;
			v = strtoll( pv, &pdummy, 10 );
#endif
		}
	}

	ret = curl_easy_setopt( easy->handle, option, v );
	EASY_DIE( ret );
}
