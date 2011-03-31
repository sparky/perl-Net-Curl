/*
 * Copyright 2011 (C) Przemyslaw Iskra <sparky at pld-linux.org>
 *
 * Loosely based on code by Cris Bailiff <c.bailiff+curl at devsecure.com>,
 * and subsequent fixes by other contributors.
 */

struct perl_curl_form_s {
	/* last seen version of this object, used in callbacks */
	SV *perl_self;

	struct curl_httppost *post, *last;
};

static perl_curl_form_t *
perl_curl_form_new( void )
{
	perl_curl_form_t *self;
	Newz( 1, self, 1, perl_curl_form_t );
	self->post = NULL;
	self->last = NULL;
	return self;
}

static void
perl_curl_form_delete( perl_curl_form_t *self )
{
	if ( self->post )
		curl_formfree( self->post );

	Safefree( self );
}

static size_t
cb_form_httppost_sv( void *arg, const char *buf, size_t len )
{
	dTHX;
	sv_catpvn( (SV *)arg, buf, len );
	return len;
}

#ifdef XS_SECTION

MODULE = WWW::CurlOO	PACKAGE = WWW::CurlOO::Form	PREFIX = curl_form_

INCLUDE: const-form-xs.inc

PROTOTYPES: ENABLE

void
curl_form_new( sclass="WWW::CurlOO::Form", base=HASHREF_BY_DEFAULT )
	const char *sclass
	SV *base
	PREINIT:
		perl_curl_form_t *self;
		HV *stash;
	PPCODE:
		if ( ! SvOK( base ) || ! SvROK( base ) )
			croak( "object base must be a valid reference\n" );

		self = perl_curl_form_new();
		perl_curl_setptr( aTHX_ base, self );

		stash = gv_stashpv( sclass, 0 );
		ST(0) = sv_bless( base, stash );

		XSRETURN(1);


void
curl_form_add( self, ... )
	WWW::CurlOO::Form self
	PROTOTYPE: $%
	PREINIT:
		struct curl_forms *farray;
		int i;
	CODE:
		if ( !(items & 1) && (
				!SvOK( ST( items - 1 ) ) ||
				sv_iv( ST( items - 1 ) ) != CURLFORM_END ) )
			croak( "Expected even number of arguments" );

		Newx( farray, (items / 2 + 1), struct curl_forms );

		for ( i = 0; i < (items - 1 ) / 2; i++ ) {
			farray[ i ].option = sv_iv( ST( i*2+1 ) );
			farray[ i ].value = SvPV_nolen( ST( i*2 + 2 ) );
		}
		farray[ i ].option = CURLFORM_END;

		curl_formadd( &self->post, &self->last,
			CURLFORM_ARRAY, farray, CURLFORM_END );

		Safefree( farray );


SV *
curl_form_get( self )
	WWW::CurlOO::Form self
	PREINIT:
		SV *output;
	CODE:
		output = newSVpv( "", 0 );
		curl_formget( self->post, output, cb_form_httppost_sv );
		RETVAL = output;
	OUTPUT:
		RETVAL


void
curl_form_DESTROY(self)
	WWW::CurlOO::Form self
	CODE:
		perl_curl_form_delete( self );

#endif
#// vim:ts=4:sw=4
