/* vim: ts=4:sw=4:ft=xs:fdm=marker: */
/*
 * Copyright 2011 (C) Przemyslaw Iskra <sparky at pld-linux.org>
 *
 * Loosely based on code by Cris Bailiff <c.bailiff+curl at devsecure.com>,
 * and subsequent fixes by other contributors.
 */


struct perl_curl_share_s {
	/* last seen version of this object */
	SV *perl_self;

#ifdef USE_ITHREADS
	perl_mutex mutex[ CURL_LOCK_DATA_LAST ];

	perl_mutex mutex_threads;
	long threads;
#endif

	/* curl share handle */
	CURLSH *handle;
};

#ifdef USE_ITHREADS
static void
cb_share_lock( CURL *easy_handle, curl_lock_data data, curl_lock_access locktype,
		void *userptr )
{
	dTHX;
	perl_curl_share_t *share = userptr;

	MUTEX_LOCK( &( share->mutex[ data ] ) );
	return;
}

static void
cb_share_unlock( CURL *easy_handle, curl_lock_data data, void *userptr )
{
	dTHX;
	perl_curl_share_t *share = userptr;

	MUTEX_UNLOCK( &( share->mutex[ data ] ) );
	return;
}

#ifdef CALLBACK_TYPECHECK
static curl_lock_function pct_lock __attribute__((unused)) = cb_share_lock;
static curl_unlock_function pct_unlock __attribute__((unused)) = cb_share_unlock;
#endif
#endif

/* make a new share */
static perl_curl_share_t *
perl_curl_share_new( pTHX )
{
	int i;
	perl_curl_share_t *share;
	Newxz( share, 1, perl_curl_share_t );
	share->handle = curl_share_init();

#ifdef USE_ITHREADS
	for ( i = CURL_LOCK_DATA_NONE; i < CURL_LOCK_DATA_LAST; i++ )
		MUTEX_INIT( &(share->mutex[ i ]) );
	MUTEX_INIT( &share->mutex_threads );
	share->threads = 1;

	curl_share_setopt( share->handle,
		CURLSHOPT_LOCKFUNC,
		cb_share_lock
	);
	curl_share_setopt( share->handle,
		CURLSHOPT_UNLOCKFUNC,
		cb_share_unlock
	);
	curl_share_setopt( share->handle,
		CURLSHOPT_USERDATA,
		share
	);
#endif
	return share;
}

static int
perl_curl_share_magic_dup( pTHX_ MAGIC *mg, CLONE_PARAMS *param )
{
#ifdef USE_ITHREADS
	perl_curl_share_t *share = (perl_curl_share_t *) mg->mg_ptr;

	MUTEX_LOCK( &share->mutex_threads );
	share->threads++;
	MUTEX_UNLOCK( &share->mutex_threads );
#else
	warn( "WWW::CurlOO::Share does supports cloning only under ithreads\n" );
	mg->mg_ptr = NULL;
#endif
	return 0;
}


/* delete the share */
static void
perl_curl_share_delete( pTHX_ perl_curl_share_t *share )
{
#ifdef USE_ITHREADS
	long i;

	MUTEX_LOCK( &share->mutex_threads );
	i = --share->threads;
	MUTEX_UNLOCK( &share->mutex_threads );

	/* some other thread is using it */
	if ( i )
		return;
#endif

	/* this may trigger some callbacks */
	curl_share_cleanup( share->handle );

#ifdef USE_ITHREADS
	for ( i = CURL_LOCK_DATA_NONE; i < CURL_LOCK_DATA_LAST; i++ )
		MUTEX_DESTROY( &(share->mutex[ i ]) );
	MUTEX_DESTROY( &share->mutex_threads );
#endif

	Safefree( share );
}

static int
perl_curl_share_magic_free( pTHX_ SV *sv, MAGIC *mg )
{
	perl_curl_share_t *share = (perl_curl_share_t *) mg->mg_ptr;
	if ( share ) {
		perl_curl_share_delete( aTHX_ share );
	}
	return 0;
}

static MGVTBL perl_curl_share_vtbl = {
	NULL, NULL, NULL, NULL
	,perl_curl_share_magic_free
	,NULL
	,perl_curl_share_magic_dup
#ifdef MGf_LOCAL
	,NULL
#endif
};


MODULE = WWW::CurlOO	PACKAGE = WWW::CurlOO::Share

INCLUDE: const-share-xs.inc

PROTOTYPES: ENABLE

void
new( sclass="WWW::CurlOO::Share", base=HASHREF_BY_DEFAULT )
	const char *sclass
	SV *base
	PREINIT:
		perl_curl_share_t *share;
		HV *stash;
	PPCODE:
		if ( ! SvOK( base ) || ! SvROK( base ) )
			croak( "object base must be a valid reference\n" );

		share = perl_curl_share_new( aTHX );
		perl_curl_setptr( aTHX_ base, &perl_curl_share_vtbl, share );

		stash = gv_stashpv( sclass, 0 );
		ST(0) = sv_bless( base, stash );

		share->perl_self = NULL;

		XSRETURN(1);


void
setopt( share, option, value )
	WWW::CurlOO::Share share
	int option
	SV * value
	PREINIT:
		CURLSHcode ret1 = CURLSHE_OK, ret2 = CURLSHE_OK;
	CODE:
		switch ( option ) {
			case CURLSHOPT_LOCKFUNC:
			case CURLSHOPT_UNLOCKFUNC:
			case CURLSHOPT_USERDATA:
				croak( "Lockling is implemented internally" );
				break;
			case CURLSHOPT_SHARE:
			case CURLSHOPT_UNSHARE:
				ret1 = curl_share_setopt( share->handle,
					option, (long) SvIV( value ) );
				break;
			default:
				ret1 = CURLSHE_BAD_OPTION;
				break;
		};
		if ( ret1 != CURLSHE_OK || ( ret1 = ret2 ) != CURLSHE_OK )
			die_code( "Share", ret1 );


SV *
strerror( ... )
	PROTOTYPE: $;$
	PREINIT:
		const char *errstr;
	CODE:
		if ( items < 1 || items > 2 )
			croak( "Usage: WWW::CurlOO::Share::strerror( [share], errnum )" );
		errstr = curl_share_strerror( SvIV( ST( items - 1 ) ) );
		RETVAL = newSVpv( errstr, 0 );
	OUTPUT:
		RETVAL
