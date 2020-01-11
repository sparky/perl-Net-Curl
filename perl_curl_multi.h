#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <curl/multi.h>

#include "perl_curl.h"

typedef enum {
	CB_MULTI_SOCKET = 0,
	CB_MULTI_TIMER,
	CB_MULTI_LAST,
} perl_curl_multi_callback_code_t;

struct perl_curl_multi_s {
	/* last seen version of this object */
	SV *perl_self;

	/* curl multi handle */
	CURLM *handle;

	/* list of callbacks */
	callback_t cb[ CB_MULTI_LAST ];

	/* list of data assigned to sockets */
	/* key: socket fd; value: user sv */
	simplell_t *socket_data;

	/* list of easy handles attached to this multi */
	/* key: our easy pointer, value: easy SV */
	simplell_t *easies;
};

typedef struct perl_curl_multi_s perl_curl_multi_t;
