/* vim: ts=4:sw=4:ft=xs:fdm=marker: */
/*
 * Copyright 2011 (C) Przemyslaw Iskra <sparky at pld-linux.org>
 *
 */

typedef IV WWW__CurlOO__EasyCode;
typedef IV WWW__CurlOO__FormCode;
typedef IV WWW__CurlOO__MultiCode;
typedef IV WWW__CurlOO__ShareCode;


MODULE = WWW::CurlOO	PACKAGE = WWW::CurlOO::EasyCode

FALLBACK: TRUE

BOOT:
	/* xsubpp registers only one package, it is not this one */
	sv_setsv(
		get_sv( "WWW::CurlOO::EasyCode::()", TRUE ),
		&PL_sv_yes
	);
	newXSproto( "WWW::CurlOO::EasyCode::()", XS_WWW__CurlOO__ShareCode_nil, file, "$;@" );


WWW::CurlOO::EasyCode
new( sclass="WWW::CurlOO::EasyCode", value=CURLE_OK )
	const char *sclass
	int value
	CODE:
		if ( value < 0 || value > CURL_LAST )
			croak( "value %d is out of CURLcode range", value );
		RETVAL = value;
	OUTPUT:
		RETVAL


IV
integer( code, ... )
	WWW::CurlOO::EasyCode code
	OVERLOAD: 0+ bool
	CODE:
		RETVAL = code;
	OUTPUT:
		RETVAL


const char *
string( code, ... )
	WWW::CurlOO::EasyCode code
	OVERLOAD: \"\"
	CODE:
		RETVAL = curl_easy_strerror( code );
	OUTPUT:
		RETVAL


MODULE = WWW::CurlOO	PACKAGE = WWW::CurlOO::FormCode

FALLBACK: TRUE

BOOT:
	/* xsubpp registers only one package, it is not this one */
	sv_setsv(
		get_sv( "WWW::CurlOO::FormCode::()", TRUE ),
		&PL_sv_yes
	);
	newXSproto( "WWW::CurlOO::FormCode::()", XS_WWW__CurlOO__ShareCode_nil, file, "$;@" );


WWW::CurlOO::FormCode
new( sclass="WWW::CurlOO::FormCode", value=CURL_FORMADD_OK )
	const char *sclass
	int value
	CODE:
		if ( value < CURL_FORMADD_OK || value > CURL_FORMADD_LAST )
			croak( "value %d is out of CURLFORMcode range", value );
		RETVAL = value;
	OUTPUT:
		RETVAL


IV
integer( code, ... )
	WWW::CurlOO::FormCode code
	OVERLOAD: 0+ bool
	CODE:
		RETVAL = code;
	OUTPUT:
		RETVAL


const char *
string( code, ... )
	WWW::CurlOO::FormCode code
	OVERLOAD: \"\"
	CODE:
		static const char * const code_names[] = {
			[CURL_FORMADD_OK]			= "OK",
			[CURL_FORMADD_MEMORY]		= "Memory",
			[CURL_FORMADD_OPTION_TWICE]	= "Option twice",
			[CURL_FORMADD_NULL]			= "NULL",
			[CURL_FORMADD_UNKNOWN_OPTION] = "Unknown option",
			[CURL_FORMADD_INCOMPLETE]	= "Incomplete",
			[CURL_FORMADD_ILLEGAL_ARRAY] = "Illegal array",
			[CURL_FORMADD_DISABLED]		= "Disabled",
			[CURL_FORMADD_LAST]			= "Last"
		};

		RETVAL = code_names[ code ];
		if ( ! RETVAL )
			croak( "WWW::CurlOO::FormCode: error string for CURLFORMcode %d is missing\n", code );
	OUTPUT:
		RETVAL



MODULE = WWW::CurlOO	PACKAGE = WWW::CurlOO::MultiCode

FALLBACK: TRUE

BOOT:
	/* xsubpp registers only one package, it is not this one */
	sv_setsv(
		get_sv( "WWW::CurlOO::MultiCode::()", TRUE ),
		&PL_sv_yes
	);
	newXSproto( "WWW::CurlOO::MultiCode::()", XS_WWW__CurlOO__ShareCode_nil, file, "$;@" );


WWW::CurlOO::MultiCode
new( sclass="WWW::CurlOO::MultiCode", value=CURLM_OK )
	const char *sclass
	int value
	CODE:
		if ( value < CURLM_CALL_MULTI_PERFORM || value > CURLM_LAST )
			croak( "value %d is out of CURLMcode range", value );
		RETVAL = value;
	OUTPUT:
		RETVAL


IV
integer( code, ... )
	WWW::CurlOO::MultiCode code
	OVERLOAD: 0+ bool
	CODE:
		RETVAL = code;
	OUTPUT:
		RETVAL


const char *
string( code, ... )
	WWW::CurlOO::MultiCode code
	OVERLOAD: \"\"
	CODE:
		RETVAL = curl_multi_strerror( code );
	OUTPUT:
		RETVAL


MODULE = WWW::CurlOO	PACKAGE = WWW::CurlOO::ShareCode

FALLBACK: TRUE

BOOT:
	/* this one should be registered already */


WWW::CurlOO::ShareCode
new( sclass="WWW::CurlOO::ShareCode", value=CURLSHE_OK )
	const char *sclass
	int value
	CODE:
		if ( value < CURLSHE_OK || value > CURLSHE_LAST )
			croak( "value %d is out of CURLSHcode range", value );
		RETVAL = value;
	OUTPUT:
		RETVAL


IV
integer( code, ... )
	WWW::CurlOO::ShareCode code
	OVERLOAD: 0+ bool
	CODE:
		RETVAL = code;
	OUTPUT:
		RETVAL


const char *
string( code, ... )
	WWW::CurlOO::ShareCode code
	OVERLOAD: \"\"
	CODE:
		RETVAL = curl_share_strerror( code );
	OUTPUT:
		RETVAL

