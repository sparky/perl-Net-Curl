MODULE = WWW::CurlOO	PACKAGE = WWW::CurlOO::Easy	PREFIX = curl_easy_

INCLUDE: const-easy-xs.inc

PROTOTYPES: ENABLE

void
curl_easy_new( sclass="WWW::CurlOO::Easy", base=HASHREF_BY_DEFAULT )
	const char *sclass
	SV *base
	PREINIT:
		perl_curl_easy_t *self;
		HV *stash;
	PPCODE:
		if ( ! SvOK( base ) || ! SvROK( base ) )
			croak( "object base must be a valid reference\n" );

		self = perl_curl_easy_new();

		Newxz( self->y, 1, I32 );
		if ( !self->y )
			croak ("out of memory");
		(*self->y)++;

		/* configure curl to always callback to the XS interface layer */
		curl_easy_setopt( self->curl, CURLOPT_WRITEFUNCTION, cb_easy_write );
		curl_easy_setopt( self->curl, CURLOPT_READFUNCTION, cb_easy_read );

		/* set our own object as the context for all curl callbacks */
		curl_easy_setopt( self->curl, CURLOPT_FILE, self );
		curl_easy_setopt( self->curl, CURLOPT_INFILE, self );

		/* we always collect this, in case it's wanted */
		curl_easy_setopt( self->curl, CURLOPT_ERRORBUFFER, self->errbuf );

		perl_curl_setptr( aTHX_ base, self );
		stash = gv_stashpv( sclass, 0 );
		ST(0) = sv_bless( base, stash );

		XSRETURN(1);


void
curl_easy_duphandle( self, base=HASHREF_BY_DEFAULT )
	WWW::CurlOO::Easy self
	SV *base
	PREINIT:
		perl_curl_easy_t *clone;
		char *sclass = "WWW::CurlOO::Easy";
		perl_curl_easy_callback_code_t i;
		HV *stash;
	PPCODE:
		/* {{{ */
		if ( ! SvOK( base ) || ! SvROK( base ) )
			croak( "object base must be a valid reference\n" );

		clone=perl_curl_easy_duphandle(self);
		clone->y = self->y;
		(*self->y)++;

		/* configure curl to always callback to the XS interface layer */

		curl_easy_setopt(clone->curl, CURLOPT_WRITEFUNCTION, cb_easy_write);
		curl_easy_setopt(clone->curl, CURLOPT_READFUNCTION, cb_easy_read);
		if (self->cb[callback_index(CURLOPT_HEADERFUNCTION)].func || self->cb[callback_index(CURLOPT_WRITEHEADER)].data) {
			curl_easy_setopt(clone->curl, CURLOPT_HEADERFUNCTION, cb_easy_header);
			curl_easy_setopt(clone->curl, CURLOPT_WRITEHEADER, clone);
		}

		if (self->cb[callback_index(CURLOPT_PROGRESSFUNCTION)].func || self->cb[callback_index(CURLOPT_PROGRESSDATA)].data) {
			curl_easy_setopt(clone->curl, CURLOPT_PROGRESSFUNCTION, cb_easy_progress);
			curl_easy_setopt(clone->curl, CURLOPT_PROGRESSDATA, clone);
		}

		if (self->cb[callback_index(CURLOPT_DEBUGFUNCTION)].func || self->cb[callback_index(CURLOPT_DEBUGDATA)].data) {
			curl_easy_setopt(clone->curl, CURLOPT_DEBUGFUNCTION, cb_easy_debug);
			curl_easy_setopt(clone->curl, CURLOPT_DEBUGDATA, clone);
		}

		/* set our own object as the context for all curl callbacks */
		curl_easy_setopt(clone->curl, CURLOPT_FILE, clone);
		curl_easy_setopt(clone->curl, CURLOPT_INFILE, clone);
		curl_easy_setopt(clone->curl, CURLOPT_ERRORBUFFER, clone->errbuf);

		for(i=0;i<CALLBACK_LAST;i++) {
			perl_curl_easy_register_callback( aTHX_ clone,&(clone->cb[i].func), self->cb[i].func);
			perl_curl_easy_register_callback( aTHX_ clone,&(clone->cb[i].data), self->cb[i].data);
		};

		for (i=0;i<=self->strings_index;i++) {
			if (self->strings[i] != NULL) {
				clone->strings[i] = savepv(self->strings[i]);
				curl_easy_setopt(clone->curl, CURLOPTTYPE_OBJECTPOINT + i, clone->strings[i]);
			}
		}
		clone->strings_index = self->strings_index;

		perl_curl_setptr( aTHX_ base, clone );
		stash = gv_stashpv( sclass, 0 );
		ST(0) = sv_bless( base, stash );

		XSRETURN(1);
		/* }}} */


int
curl_easy_setopt( self, option, value )
	WWW::CurlOO::Easy self
	int option
	SV *value
	CODE:
		/* {{{ */
		RETVAL=CURLE_OK;
		switch( option ) {
			/* SV * to user contexts for callbacks - any SV (glob,scalar,ref) */
			case CURLOPT_FILE:
			case CURLOPT_INFILE:
				perl_curl_easy_register_callback( aTHX_ self,
						&(self->cb[callback_index(option)].data), value);
				break;
			case CURLOPT_WRITEHEADER:
				curl_easy_setopt(self->curl, CURLOPT_HEADERFUNCTION, SvOK(value) ? cb_easy_header : NULL);
				curl_easy_setopt(self->curl, option, SvOK(value) ? self : NULL);
				perl_curl_easy_register_callback( aTHX_ self,&(self->cb[callback_index(option)].data),value);
				break;
			case CURLOPT_PROGRESSDATA:
				curl_easy_setopt(self->curl, CURLOPT_PROGRESSFUNCTION, SvOK(value) ? cb_easy_progress : NULL);
				curl_easy_setopt(self->curl, option, SvOK(value) ? self : NULL);
				perl_curl_easy_register_callback( aTHX_ self,&(self->cb[callback_index(option)].data), value);
				break;
			case CURLOPT_DEBUGDATA:
				curl_easy_setopt(self->curl, CURLOPT_DEBUGFUNCTION, SvOK(value) ? cb_easy_debug : NULL);
				curl_easy_setopt(self->curl, option, SvOK(value) ? self : NULL);
				perl_curl_easy_register_callback( aTHX_ self,&(self->cb[callback_index(option)].data), value);
				break;

			/* SV * to a subroutine ref */
			case CURLOPT_WRITEFUNCTION:
			case CURLOPT_READFUNCTION:
				perl_curl_easy_register_callback( aTHX_ self,&(self->cb[callback_index(option)].func), value);
				break;
			case CURLOPT_HEADERFUNCTION:
				curl_easy_setopt(self->curl, option, SvOK(value) ? cb_easy_header : NULL);
				curl_easy_setopt(self->curl, CURLOPT_WRITEHEADER, SvOK(value) ? self : NULL);
				perl_curl_easy_register_callback( aTHX_ self,&(self->cb[callback_index(option)].func), value);
				break;
			case CURLOPT_PROGRESSFUNCTION:
				curl_easy_setopt(self->curl, option, SvOK(value) ? cb_easy_progress : NULL);
				curl_easy_setopt(self->curl, CURLOPT_PROGRESSDATA, SvOK(value) ? self : NULL);
				perl_curl_easy_register_callback( aTHX_ self,&(self->cb[callback_index(option)].func), value);
				break;
			case CURLOPT_DEBUGFUNCTION:
				curl_easy_setopt(self->curl, option, SvOK(value) ? cb_easy_debug : NULL);
				curl_easy_setopt(self->curl, CURLOPT_DEBUGDATA, SvOK(value) ? self : NULL);
				perl_curl_easy_register_callback( aTHX_ self,&(self->cb[callback_index(option)].func), value);
				break;

			/* slist cases */
			case CURLOPT_HTTPHEADER:
			case CURLOPT_HTTP200ALIASES:
#ifdef CURLOPT_MAIL_RCPT
			case CURLOPT_MAIL_RCPT:
#endif
			case CURLOPT_QUOTE:
			case CURLOPT_POSTQUOTE:
			case CURLOPT_PREQUOTE:
#ifdef CURLOPT_RESOLVE
			case CURLOPT_RESOLVE:
#endif
			case CURLOPT_TELNETOPTIONS:
				RETVAL = perl_curl_easy_setoptslist( aTHX_ self, option, value, 1 );
				if ( RETVAL == -1 )
					croak( "Specified option does not accept slists" );
				break;

			/* Pass in variable name for storing error messages. Yuck. */
			/* XXX: fix this */
			case CURLOPT_ERRORBUFFER:
			{
				STRLEN dummy;
				if (self->errbufvarname)
					free(self->errbufvarname);
				self->errbufvarname = strdup((char *)SvPV(value, dummy));
			};
				break;

			/* tell curl to redirect STDERR - value should be a glob */
			case CURLOPT_STDERR:
				RETVAL = curl_easy_setopt(self->curl, option, PerlIO_findFILE( IoOFP(sv_2io(value)) ) );
				break;

			/* not working yet... */
			case CURLOPT_HTTPPOST:
				if (sv_derived_from(value, "WWW::CurlOO::Form")) {
					WWW__CurlOO__Form wrapper;
					wrapper = perl_curl_getptr( aTHX_ value );
					RETVAL = curl_easy_setopt(self->curl, option, wrapper->post);
				} else
					croak("value is not of type WWW::CurlOO::Form");
				break;

			/* Curl share support from Anton Fedorov */
			case CURLOPT_SHARE:
				if (sv_derived_from(value, "WWW::CurlOO::Share")) {
					WWW__CurlOO__Share wrapper;
					wrapper = perl_curl_getptr( aTHX_ value );
					RETVAL = curl_easy_setopt(self->curl, option, wrapper->curlsh);
					if ( RETVAL = CURLE_OK )
						self->share = wrapper;
				} else
					croak("value is not of type WWW::CurlOO::Share");
				break;

			case CURLOPT_PRIVATE:
				croak( "CURLOPT_PRIVATE is off limits" );
				break;

			/* default cases */
			default:
				if (option < CURLOPTTYPE_OBJECTPOINT) { /* A long (integer) value */
					RETVAL = curl_easy_setopt(self->curl, option, (long)SvIV(value));
				}
				else if (option < CURLOPTTYPE_FUNCTIONPOINT) { /* An objectpoint - string */
					int string_index = option - CURLOPTTYPE_OBJECTPOINT;
					/* FIXME: Does curl really want NULL for empty strings? */
					STRLEN dummy = 0;
					/* Pre 7.17.0, the strings aren't copied by libcurl.*/
					char* pv = SvOK(value) ? SvPV(value, dummy) : "";
					I32 len = (I32)dummy;
					pv = savepvn(pv, len);
					if (self->strings[string_index] != NULL)
						Safefree(self->strings[string_index]);
					self->strings[string_index] = pv;
					if (self->strings_index < string_index)
						self->strings_index = string_index;
					RETVAL = curl_easy_setopt(self->curl, option, SvOK(value) ? pv : NULL);
				}
				else if (option < CURLOPTTYPE_OFF_T) { /* A function - notreached? */
					croak("Unknown curl option of type function");
				}
				else { /* A LARGE file option using curl_off_t, handling larger than 32bit sizes without 64bit integer support */
					if (SvOK(value) && looks_like_number(value)) {
						STRLEN dummy = 0;
						char* pv = SvPV(value, dummy);
						char* pdummy;
						RETVAL = curl_easy_setopt(self->curl, option, (curl_off_t) strtoll(pv,&pdummy,10));
					} else {
						RETVAL = 0;
					}
				};
				break;
		};
		/* }}} */
	OUTPUT:
		RETVAL


int
curl_easy_pushopt(self, option, value)
	WWW::CurlOO::Easy self
	int option
	SV *value
	CODE:
		RETVAL = perl_curl_easy_setoptslist( aTHX_ self, option, value, 0 );
		if ( RETVAL == -1 )
			croak( "Specified option does not accept slists" );
	OUTPUT:
		RETVAL


int
curl_easy_perform(self)
	WWW::CurlOO::Easy self
	CODE:
		/* {{{ */
		perl_curl_easy_update( self, ST(0) );
		/* perform the actual curl fetch */
		RETVAL = curl_easy_perform(self->curl);

		if (RETVAL && self->errbufvarname) {
			/* If an error occurred and a varname for error messages has been
			specified, store the error message. */
			SV *sv = perl_get_sv(self->errbufvarname, TRUE | GV_ADDMULTI);
			sv_setpv(sv, self->errbuf);
		}
		/* }}} */
	OUTPUT:
		RETVAL


SV *
curl_easy_getinfo( self, option )
	WWW::CurlOO::Easy self
	int option
	CODE:
		/* {{{ */
		switch( option & CURLINFO_TYPEMASK ) {
			case CURLINFO_STRING:
			{
				char * vchar;
				curl_easy_getinfo(self->curl, option, &vchar);
				RETVAL = newSVpv(vchar,0);
				break;
			}
			case CURLINFO_LONG:
			{
				long vlong;
				curl_easy_getinfo(self->curl, option, &vlong);
				RETVAL = newSViv(vlong);
				break;
			}
			case CURLINFO_DOUBLE:
			{
				double vdouble;
				curl_easy_getinfo(self->curl, option, &vdouble);
				RETVAL = newSVnv(vdouble);
				break;
			}
			case CURLINFO_SLIST:
			{
				struct curl_slist *vlist, *entry;
				AV *items = newAV();
				curl_easy_getinfo(self->curl, option, &vlist);
				if (vlist != NULL) {
					entry = vlist;
					while (entry) {
						av_push(items, newSVpv(entry->data, 0));
						entry = entry->next;
					}
					curl_slist_free_all(vlist);
				}
				RETVAL = newRV(sv_2mortal((SV *) items));
				break;
			}
			default: {
				croak( "invalid getinfo option" );
				break;
			}
		}
		/* }}} */
	OUTPUT:
		RETVAL

char *
curl_easy_errbuf(self)
	WWW::CurlOO::Easy self
	CODE:
		RETVAL = self->errbuf;
	OUTPUT:
		RETVAL

size_t
curl_easy_send( self, buffer )
	WWW::CurlOO::Easy self
	SV *buffer
	CODE:
		/* {{{ */
#if LIBCURL_VERSION_NUM >= 0x071202
		CURLcode ret;
		STRLEN len;
		const char *pv;
		size_t out_len;

		if ( ! SvOK( buffer ) )
			croak( "buffer is not valid\n" );

		pv = SvPV( buffer, len );
		ret = curl_easy_send( self->curl, pv, len, &out_len );
		if ( ret != CURLE_OK )
			croak( "curl_easy_send() didn't return CURLE_OK\n" );

		RETVAL = out_len;
#else
		croak( "curl_easy_send() not available in curl before 7.18.2\n" );
		RETVAL = 0;
#endif
		/* }}} */
	OUTPUT:
		RETVAL

int
curl_easy_recv( self, buffer, length )
	WWW::CurlOO::Easy self
	SV *buffer
	size_t length
	CODE:
		/* {{{ */
#if LIBCURL_VERSION_NUM >= 0x071202
		CURLcode ret;
		size_t out_len;
		char *tmpbuf;

		Newx( tmpbuf, length, char);
		ret = curl_easy_recv( self->curl, tmpbuf, length, &out_len );
		if ( ret != CURLE_OK )
			sv_setsv( buffer, &PL_sv_undef );
		else
			sv_setpvn( buffer, tmpbuf, out_len );

		Safefree( tmpbuf );
		RETVAL = ret;
#else
		croak( "curl_easy_recv() not available in curl before 7.18.2\n" );
		RETVAL = 0;
#endif
		/* }}} */
	OUTPUT:
		RETVAL


void
curl_easy_DESTROY(self)
	WWW::CurlOO::Easy self
	CODE:
		perl_curl_easy_delete( aTHX_ self );


SV *
curl_easy_strerror(self, errornum)
	WWW::CurlOO::Easy self
	int errornum
	PREINIT:
		const char *errstr;
	CODE:
		errstr = curl_easy_strerror( errornum );
		RETVAL = newSVpv( errstr, 0 );
	OUTPUT:
		RETVAL

