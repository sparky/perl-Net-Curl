/* vim: ts=4:sw=4:ft=xs:fdm=marker: */
/*
 * Copyright 2011 (C) Przemyslaw Iskra <sparky at pld-linux.org>
 *
 * Loosely based on code by Cris Bailiff <c.bailiff+curl at devsecure.com>,
 * and subsequent fixes by other contributors.
 */

enum {
	CB_FORM_GET,
	CB_FORM_LAST
};

struct perl_curl_form_s {
	/* last seen version of this object, used in callbacks */
	SV *perl_self;

	struct curl_httppost *post, *last;

	callback_t cb[ CB_FORM_LAST ];
};

static perl_curl_form_t *
perl_curl_form_new( void )
{
	perl_curl_form_t *form;
	Newxz( form, 1, perl_curl_form_t );
	form->post = NULL;
	form->last = NULL;
	return form;
}

static void
perl_curl_form_delete( pTHX_ perl_curl_form_t *form )
{
	sv_2mortal( form->perl_self );

	if ( form->post )
		curl_formfree( form->post );

	Safefree( form );
}

/* callback: append to a scalar */
static size_t
cb_form_get_sv( void *arg, const char *buf, size_t len )
{
	dTHX;
	sv_catpvn( (SV *) arg, buf, len );
	return len;
}

/* callback: print to perl io */
static size_t
cb_form_get_io( void *arg, const char *buf, size_t len )
{
	dTHX;
	return PerlIO_write( (PerlIO *) arg, buf, len );
}

/* callback: execute a callback */
static size_t
cb_form_get_code( void *arg, const char *buf, size_t len )
{
	dTHX;

	perl_curl_form_t *form = arg;

	/* $form, $buffer, [$userdata] */
	SV *args[] = {
		newSVsv( form->perl_self ),
		newSVpvn( buf, len )
	};

	return PERL_CURL_CALL( &form->cb[ CB_FORM_GET ], args );
}

static int
perl_curl_form_magic_free( pTHX_ SV *sv, MAGIC *mg )
{
	if ( mg->mg_ptr )
		perl_curl_form_delete( aTHX_ (void *) mg->mg_ptr );
	return 0;
}

static MGVTBL perl_curl_form_vtbl = {
	NULL, NULL, NULL, NULL
	,perl_curl_form_magic_free
	,NULL
	,perl_curl_any_magic_nodup
#ifdef MGf_LOCAL
	,NULL
#endif
};



MODULE = WWW::CurlOO	PACKAGE = WWW::CurlOO::Form

INCLUDE: const-form-xs.inc

PROTOTYPES: ENABLE

void
new( sclass="WWW::CurlOO::Form", base=HASHREF_BY_DEFAULT )
	const char *sclass
	SV *base
	PREINIT:
		perl_curl_form_t *form;
		HV *stash;
	PPCODE:
		if ( ! SvOK( base ) || ! SvROK( base ) )
			croak( "object base must be a valid reference\n" );

		form = perl_curl_form_new();
		perl_curl_setptr( aTHX_ base, &perl_curl_form_vtbl, form );

		stash = gv_stashpv( sclass, 0 );
		ST(0) = sv_bless( base, stash );

		form->perl_self = newSVsv( ST(0) );
		sv_rvweaken( form->perl_self );

		XSRETURN(1);


void
add( form, ... )
	WWW::CurlOO::Form form
	PROTOTYPE: $%
	PREINIT:
		struct curl_forms *farray;
		int i_in, i_out;
		CURLFORMcode ret;
	CODE:
		if ( !( items & 1 ) && (
				!SvOK( ST( items - 1 ) ) ||
				sv_iv( ST( items - 1 ) ) != CURLFORM_END ) )
			croak( "Expected even number of arguments" );

		/* items is about twice as much as we'll normally use */
		Newx( farray, items, struct curl_forms );

		for ( i_in = 1, i_out = 0; i_in < items - 1; i_in += 2 ) {
			int option = sv_iv( ST( i_in ) );
			int option_len;
			STRLEN len;
			switch ( option ) {
				/* set string and its length */
				case CURLFORM_COPYNAME:
					option_len = CURLFORM_NAMELENGTH;
					goto case_datawithzero;
				case CURLFORM_COPYCONTENTS:
					option_len = CURLFORM_CONTENTSLENGTH;
				/*	TODO: must make a copy of the buffer
					goto case_datawithzero;
				case CURLFORM_BUFFERPTR:
					option_len = CURLFORM_BUFFERLENGTH;*/
case_datawithzero:
					farray[ i_out ].option = option;
					farray[ i_out ].value = SvPV( ST( i_in + 1 ), len );
					i_out++;
					farray[ i_out ].option = option_len;
					farray[ i_out ].value = (void *) len;
					i_out++;
					break;

				case CURLFORM_NAMELENGTH:
				case CURLFORM_CONTENTSLENGTH:
				/*case CURLFORM_BUFFERLENGTH:*/
					if ( i_out > 0 && farray[ i_out - 1 ].option == option )
						i_out--;
					farray[ i_out ].option = option;
					farray[ i_out ].value = (void *) sv_iv( ST( i_in + 1 ) );
					i_out++;
					break;

				case CURLFORM_FILECONTENT:
				case CURLFORM_FILE:
				case CURLFORM_CONTENTTYPE:
				case CURLFORM_FILENAME:
				/*case CURLFORM_BUFFER:*/
					farray[ i_out ].option = option;
					farray[ i_out ].value = SvPV_nolen( ST( i_in + 1 ) );
					i_out++;
					break;

				/*case CURLFORM_CONTENTHEADER:
					* This may be a problem:
					*
					* When you’ve passed the HttpPost pointer to curl_easy_setopt
					* (using the CURLOPT_HTTPPOST option), you must not free the
					* list until after you’ve called curl_easy_cleanup( for the
					* curl handle.

					farray[ i_out ].option = option;
					farray[ i_out ].value = SvPV_nolen( ST( i_in + 1 ) );
					i_out++;
					break;
					*/

				default:
					croak( "curl_formadd option %d is not supported", option );
					break;
			}
		}
		farray[ i_out ].option = CURLFORM_END;

		ret = curl_formadd( &form->post, &form->last,
			CURLFORM_ARRAY, farray, CURLFORM_END );

		Safefree( farray );

		if ( ret != CURL_FORMADD_OK )
			die_code( "Form", ret );


void
get( form, ... )
	WWW::CurlOO::Form form
	PROTOTYPE: $;$&
	PREINIT:
		SV *output;
	PPCODE:
		CLEAR_ERRSV();

		if ( items < 2 ) {
			output = sv_2mortal( newSVpv( "", 0 ) );
			curl_formget( form->post, output, cb_form_get_sv );

			/* rethrow errors */
			if ( SvTRUE( ERRSV ) )
				croak( NULL );

			ST(0) = output;
			XSRETURN(1);

		} else if ( items < 3 ) {
			output = ST(1);

			if ( SvROK( output ) )
				output = SvRV( output );

			if ( SvTYPE( output ) == SVt_PVGV ) {
				PerlIO *handle = IoOFP( sv_2io( output ) );
				curl_formget( form->post, handle, cb_form_get_io );
			} else if ( !SvREADONLY( output ) ) {
				curl_formget( form->post, output, cb_form_get_sv );
			} else {
				croak( "output buffer is invalid" );
			}

			/* rethrow errors */
			if ( SvTRUE( ERRSV ) )
				croak( NULL );

			XSRETURN(0);

		} else {
			form->cb[ CB_FORM_GET ].data = ST(1);
			form->cb[ CB_FORM_GET ].func = ST(2);
			curl_formget( form->post, form, cb_form_get_code );

			/* rethrow errors */
			if ( SvTRUE( ERRSV ) )
				croak( NULL );

			XSRETURN(0);
		}


int
CLONE_SKIP( pkg )
	SV *pkg
	CODE:
		(void ) pkg;
		RETVAL = 1;
	OUTPUT:
		RETVAL
