/*------------------------------------------------------------------------
 *  Copyright 2009 (c) Jeff Brown <spadix@users.sourceforge.net>
 *
 *  This file is part of the ZBar Bar Code Reader.
 *
 *  The ZBar Bar Code Reader is free software; you can redistribute it
 *  and/or modify it under the terms of the GNU Lesser Public License as
 *  published by the Free Software Foundation; either version 2.1 of
 *  the License, or (at your option) any later version.
 *
 *  The ZBar Bar Code Reader is distributed in the hope that it will be
 *  useful, but WITHOUT ANY WARRANTY; without even the implied warranty
 *  of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Lesser Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser Public License
 *  along with the ZBar Bar Code Reader; if not, write to the Free
 *  Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *  Boston, MA  02110-1301  USA
 *
 *  http://sourceforge.net/projects/zbar
 *------------------------------------------------------------------------*/

#include <config.h>
#ifdef HAVE_INTTYPES_H
# include <inttypes.h>
#endif
#include <stdlib.h>
#include <stdio.h>
#include <assert.h>
#include <zbar.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>

/* adapted from v4l2 spec */
#define fourcc(a, b, c, d)                      \
    ((uint32_t)(a) | ((uint32_t)(b) << 8) |     \
     ((uint32_t)(c) << 16) | ((uint32_t)(d) << 24))


__attribute__ ((export_name("create_processor")))
zbar_processor_t *create_processor(void)
{
    zbar_processor_t *proc = zbar_processor_create(0);
    if(!proc)
        return NULL;
    if(zbar_processor_init(proc, NULL, 0)) {
        zbar_processor_destroy(proc);
        return NULL;
    }
    return proc;
}

__attribute__ ((export_name("destroy_processor")))
void destroy_processor(zbar_processor_t* proc)
{
    zbar_processor_destroy(proc);
}

__attribute__ ((export_name("process_jpeg_image")))
zbar_image_t *process_jpeg_image(zbar_processor_t* proc, uint8_t* jpeg, size_t jpeg_len)
{
    zbar_image_t *img = zbar_image_create();
    zbar_image_set_format(img, fourcc('J','P','E','G'));
    zbar_image_set_data(img, jpeg, jpeg_len, NULL);

    zbar_image_t *zimage = zbar_image_convert(img, fourcc('Y','8','0','0'));
    zbar_image_destroy(img);
    if(!zimage)
        return NULL;

    if(zbar_process_image(proc, zimage) < 0) {
        zbar_image_destroy(zimage);
        return NULL;
    }

    return zimage;
}

__attribute__ ((export_name("destroy_image")))
void destroy_image(zbar_image_t* zimage)
{
    zbar_image_destroy(zimage);
}

__attribute__ ((export_name("get_image_first_symbol")))
const zbar_symbol_t *get_image_first_symbol(zbar_image_t* zimage)
{
    const zbar_symbol_t *sym = zbar_image_first_symbol(zimage);
    for(; sym; sym = zbar_symbol_next(sym)) {
        zbar_symbol_type_t typ = zbar_symbol_get_type(sym);
        if(typ != ZBAR_PARTIAL)
            return sym;
    }
    return NULL;
}

__attribute__ ((export_name("get_next_symbol")))
const zbar_symbol_t *get_next_symbol(const zbar_symbol_t* zsym)
{
    const zbar_symbol_t *sym = zbar_symbol_next(zsym);
    for(; sym; sym = zbar_symbol_next(sym)) {
        zbar_symbol_type_t typ = zbar_symbol_get_type(sym);
        if(typ != ZBAR_PARTIAL)
            return sym;
    }
    return NULL;
}

__attribute__ ((export_name("get_symbol_name")))
const char *get_symbol_name(const zbar_symbol_t* sym)
{
    zbar_symbol_type_t typ = zbar_symbol_get_type(sym);
    return zbar_get_symbol_name(typ);
}

__attribute__ ((export_name("get_addon_name")))
const char *get_addon_name(const zbar_symbol_t* sym)
{
    zbar_symbol_type_t typ = zbar_symbol_get_type(sym);
    return zbar_get_addon_name(typ);
}

__attribute__ ((export_name("get_symbol_data")))
const char *get_symbol_data(const zbar_symbol_t* sym)
{
    return zbar_symbol_get_data(sym);
}

void _start()
{
}
