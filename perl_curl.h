#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

typedef struct simplell_s simplell_t;
struct simplell_s {
	/* next in the linked list */
	simplell_t *next;

	/* curl option it belongs to */
	PTRV key;

	/* the actual data */
	void *value;
};

typedef struct {
	/* function that will be called */
	SV *func;

	/* user data */
	SV *data;
} callback_t;
