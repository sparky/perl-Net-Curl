MODULE = WWW::CurlOO	PACKAGE = WWW::CurlOO::Form	PREFIX = curl_form_

INCLUDE: const-form-xs.inc


void
curl_form_new( ... )
	PREINIT:
		perl_curl_form_t *self;
		char *sclass = "WWW::CurlOO::Form";
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

		self = perl_curl_form_new();
		perl_curl_setptr( aTHX_ base, self );

		stash = gv_stashpv( sclass, 0 );
		ST(0) = sv_bless( base, stash );

		XSRETURN(1);


void
curl_form_formadd(self,name,value)
	WWW::CurlOO::Form self
	char *name
	char *value
	CODE:
		curl_formadd(&(self->post),&(self->last),
			CURLFORM_COPYNAME,name,
			CURLFORM_COPYCONTENTS,value,
			CURLFORM_END);

void
curl_form_formaddfile(self,filename,description,type)
	WWW::CurlOO::Form self
	char *filename
	char *description
	char *type
	CODE:
		curl_formadd(&(self->post),&(self->last),
			CURLFORM_FILE,filename,
			CURLFORM_COPYNAME,description,
			CURLFORM_CONTENTTYPE,type,
			CURLFORM_END);

void
curl_form_DESTROY(self)
	WWW::CurlOO::Form self
	CODE:
		perl_curl_form_delete(self);

