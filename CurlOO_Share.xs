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
	CURLSH *curlsh;

	/* list of callbacks */
	callback_t cb[ CB_SHARE_LAST ];
};


static void
perl_curl_share_register_callback( pTHX_ perl_curl_share_t *self, SV **callback,
		SV *function )
{
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
}

/* make a new share */
static perl_curl_share_t *
perl_curl_share_new( void )
{
	perl_curl_share_t *self;
	Newxz( self, 1, perl_curl_share_t );
	self->curlsh=curl_share_init();
	return self;
}

/* delete the share */
static void
perl_curl_share_delete( pTHX_ perl_curl_share_t *self )
{
	perl_curl_share_callback_code_t i;
	if (self->curlsh)
		curl_share_cleanup(self->curlsh);

	for(i=0;i<CB_SHARE_LAST;i++) {
		sv_2mortal(self->cb[i].func);
		sv_2mortal(self->cb[i].data);
	}
	Safefree(self);
}


static void
cb_share_lock( CURL *easy, curl_lock_data data, curl_lock_access locktype,
		void *userptr )
{
	dTHX;
	dSP;

	int count;
	perl_curl_share_t *self;
	perl_curl_easy_t *peasy;

	self=(perl_curl_share_t *)userptr;
	(void) curl_easy_getinfo( easy, CURLINFO_PRIVATE, (void *)&peasy);

	ENTER;
	SAVETMPS;
	PUSHMARK(sp);

	/* $easy, $data, $locktype, $userdata */
	XPUSHs( sv_2mortal( newSVsv( peasy->perl_self ) ) );
	XPUSHs( sv_2mortal( newSViv( data ) ) );
	XPUSHs( sv_2mortal( newSViv( locktype ) ) );
	if (self->cb[CB_SHARE_LOCK].data) {
		XPUSHs(sv_2mortal(newSVsv(self->cb[CB_SHARE_LOCK].data)));
	} else {
		XPUSHs(&PL_sv_undef);
	}

	PUTBACK;
	count = perl_call_sv( self->cb[CB_SHARE_LOCK].func, G_SCALAR );
	SPAGAIN;

	if (count != 0)
		croak("callback for CURLSHOPT_LOCKFUNCTION didn't return void\n");

	PUTBACK;
	FREETMPS;
	LEAVE;
	return;
}

static void
cb_share_unlock( CURL *easy, curl_lock_data data, void *userptr )
{
	dTHX;
	dSP;

	int count;
	perl_curl_share_t *self;
	perl_curl_easy_t *peasy;

	self=(perl_curl_share_t *)userptr;
	(void) curl_easy_getinfo( easy, CURLINFO_PRIVATE, (void *)&peasy);

	ENTER;
	SAVETMPS;
	PUSHMARK(sp);

	/* $easy, $data, $userdata */
	XPUSHs( sv_2mortal( newSVsv( peasy->perl_self ) ) );
	XPUSHs( sv_2mortal( newSViv( data ) ) );
	if (self->cb[CB_SHARE_LOCK].data) {
		XPUSHs(sv_2mortal(newSVsv(self->cb[CB_SHARE_LOCK].data)));
	} else {
		XPUSHs(&PL_sv_undef);
	}

	PUTBACK;
	count = perl_call_sv( self->cb[CB_SHARE_LOCK].func, G_SCALAR );
	SPAGAIN;

	if (count != 0)
		croak("callback for CURLSHOPT_UNLOCKFUNCTION didn't return void\n");

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
		perl_curl_share_t *self;
		HV *stash;
	PPCODE:
		if ( ! SvOK( base ) || ! SvROK( base ) )
			croak( "object base must be a valid reference\n" );

		self = perl_curl_share_new();
		perl_curl_setptr( aTHX_ base, self );

		stash = gv_stashpv( sclass, 0 );
		ST(0) = sv_bless( base, stash );

		XSRETURN(1);


void
curl_share_DESTROY(self)
	WWW::CurlOO::Share self
	CODE:
		perl_curl_share_delete( aTHX_ self );

int
curl_share_setopt(self, option, value)
	WWW::CurlOO::Share self
	int option
	SV * value
	CODE:
		/* {{{ */
		RETVAL=CURLE_OK;
		switch( option ) {
			case CURLSHOPT_LOCKFUNC:
				RETVAL = curl_share_setopt( self->curlsh,
					CURLSHOPT_LOCKFUNC, SvOK( value ) ? cb_share_lock : NULL );
				curl_share_setopt( self->curlsh,
					CURLSHOPT_USERDATA, SvOK( value ) ? self : NULL );
				perl_curl_share_register_callback( aTHX_ self,
					&(self->cb[CB_SHARE_LOCK].func), value );
				break;
			case CURLSHOPT_UNLOCKFUNC:
				RETVAL = curl_share_setopt( self->curlsh,
					CURLSHOPT_UNLOCKFUNC, SvOK(value) ? cb_share_unlock : NULL );
				curl_share_setopt( self->curlsh,
					CURLSHOPT_USERDATA, SvOK(value) ? self : NULL );
				perl_curl_share_register_callback( aTHX_ self,
					&(self->cb[CB_SHARE_UNLOCK].func), value );
				break;
			case CURLSHOPT_USERDATA:
				perl_curl_share_register_callback( aTHX_ self,
					&(self->cb[CB_SHARE_LOCK].data), value );
				break;
			case CURLSHOPT_SHARE:
			case CURLSHOPT_UNSHARE:
				RETVAL = curl_share_setopt( self->curlsh, option, (long)SvIV( value ) );
				break;
			default:
				croak("Unknown curl share option");
				break;
		};
		/* }}} */
	OUTPUT:
		RETVAL


SV *
curl_share_strerror(self, errornum)
	WWW::CurlOO::Share self
	int errornum
	PREINIT:
		const char *errstr;
		(void) self; /* unused */
	CODE:
		errstr = curl_share_strerror( errornum );
		RETVAL = newSVpv( errstr, 0 );
	OUTPUT:
		RETVAL

#endif
#// vim:ts=4:sw=4
