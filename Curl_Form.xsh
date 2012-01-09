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

	long adds;
	simplell_t *buffers;
	simplell_t *slists;
};

static perl_curl_form_t *
perl_curl_form_new( void )
{
	perl_curl_form_t *form;
	Newxz( form, 1, perl_curl_form_t );
	form->post = NULL;
	form->last = NULL;
	form->adds = 0;

	return form;
}

static void
perl_curl_form_delete( pTHX_ perl_curl_form_t *form )
{
	if ( form->post )
		curl_formfree( form->post );

	SIMPLELL_FREE( form->buffers, Safefree );
	SIMPLELL_FREE( form->slists, curl_slist_free_all );

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
		SELF2PERL( form ),
		newSVpvn( buf, len )
	};

	return PERL_CURL_CALL( &form->cb[ CB_FORM_GET ], args );
}

static int
perl_curl_form_magic_free( pTHX_ SV *sv, MAGIC *mg )
{
	if ( mg->mg_ptr ) {
		/* prevent recursive destruction */
		SvREFCNT( sv ) = 1 << 30;

		perl_curl_form_delete( aTHX_ (void *) mg->mg_ptr );

		SvREFCNT( sv ) = 0;
	}
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



MODULE = Net::Curl	PACKAGE = Net::Curl::Form

INCLUDE: const-form-xs.inc

PROTOTYPES: ENABLE

void
new( sclass="Net::Curl::Form", base=HASHREF_BY_DEFAULT )
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

		form->perl_self = SvRV( ST(0) );

		XSRETURN(1);


void
add( form, ... )
	Net::Curl::Form form
	PROTOTYPE: $%
	PREINIT:
		struct curl_forms *farray;
		int i_in, i_out;
		CURLFORMcode ret;
	CODE:
		if ( !( items & 1 ) && (
				!SvOK( ST( items - 1 ) ) ||
				SvIV( ST( items - 1 ) ) != CURLFORM_END ) )
			croak( "Expected even number of arguments" );

		form->adds++;

		/* items is about twice as much as we'll normally use */
		Newx( farray, items, struct curl_forms );

		for ( i_in = 1, i_out = 0; i_in < items - 1; i_in += 2 ) {
			int option = SvIV( ST( i_in ) );
			SV *value = ST( i_in + 1 );
			int option_len = 0;
			char *buf = NULL;
			STRLEN len = 0;
			switch ( option ) {
				/* set string and its length */
				case CURLFORM_PTRNAME:
					option = CURLFORM_COPYNAME;
				case CURLFORM_COPYNAME:
					option_len = CURLFORM_NAMELENGTH;
					buf = SvPV( value, len );
					goto case_datawithzero;

				case CURLFORM_PTRCONTENTS:
					option = CURLFORM_COPYCONTENTS;
				case CURLFORM_COPYCONTENTS:
					option_len = CURLFORM_CONTENTSLENGTH;
					buf = SvPV( value, len );
					goto case_datawithzero;

				case CURLFORM_BUFFERPTR:
					option_len = CURLFORM_BUFFERLENGTH;
					if ( SvOK( value ) && SvROK( value ) )
						value = SvRV( value );
					{
						char **bufp = perl_curl_simplell_add( aTHX_
							&form->buffers, ( form->adds << 16 | i_out ) );
						char *src = SvPV( value, len );
						*bufp = buf = savepvn( src, len );
					}

				case_datawithzero:
					farray[ i_out ].option = option;
					farray[ i_out ].value = buf;
					i_out++;
					farray[ i_out ].option = option_len;
					farray[ i_out ].value = (void *) len;
					i_out++;
					break;

				case CURLFORM_NAMELENGTH:
				case CURLFORM_CONTENTSLENGTH:
				case CURLFORM_BUFFERLENGTH:
					if ( i_out > 0 && farray[ i_out - 1 ].option == option ) {
						if ( PTR2IV( farray[ i_out - 1 ].value ) < SvIV( value ) )
							croak( "specified length larger than data size" );
						i_out--;
					}
					farray[ i_out ].option = option;
					farray[ i_out ].value = INT2PTR( void *, SvIV( value ) );
					i_out++;
					break;

				case CURLFORM_FILECONTENT:
				case CURLFORM_FILE:
				case CURLFORM_CONTENTTYPE:
				case CURLFORM_FILENAME:
				case CURLFORM_BUFFER:
					farray[ i_out ].option = option;
					farray[ i_out ].value = SvPV_nolen( value );
					i_out++;
					break;

				case CURLFORM_CONTENTHEADER:
					{
						struct curl_slist **pslist;
						pslist = perl_curl_simplell_add( aTHX_ &form->slists,
							( form->adds << 16 | i_out ) );
						*pslist = perl_curl_array2slist( aTHX_ NULL, value );

						farray[ i_out ].option = option;
						farray[ i_out ].value = (void *) *pslist;
						i_out++;
					}
					break;

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
	Net::Curl::Form form
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
