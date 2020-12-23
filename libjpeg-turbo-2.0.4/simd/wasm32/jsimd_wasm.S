/*
 * Wasm SIMD optimizations for libjpeg-turbo
 *
 * Copyright (C) 2020, Mozilla Foundation.  All Rights Reserved.
 *
 * This software is provided 'as-is', without any express or implied
 * warranty.  In no event will the authors be held liable for any damages
 * arising from the use of this software.
 *
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 *
 * 1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 */

/* Supplementary macro for setting function attributes */
.macro asm_function fname, params, returns
    .global \fname
    .hidden \fname
    .type \fname, @function
\fname:
    .functype   \fname \params -> \returns
.endm

#define F_0_298   2446  /* FIX(0.298631336) */
#define F_0_390   3196  /* FIX(0.390180644) */
#define F_0_541   4433  /* FIX(0.541196100) */
#define F_0_765   6270  /* FIX(0.765366865) */
#define F_0_899   7373  /* FIX(0.899976223) */
#define F_1_175   9633  /* FIX(1.175875602) */
#define F_1_501  12299  /* FIX(1.501321110) */
#define F_1_847  15137  /* FIX(1.847759065) */
#define F_1_961  16069  /* FIX(1.961570560) */
#define F_2_053  16819  /* FIX(2.053119869) */
#define F_2_562  20995  /* FIX(2.562915447) */
#define F_3_072  25172  /* FIX(3.072711026) */

#define F130_F054 10703   /* (F_0_541 + F_0_765) */
#define F054_MF130 -10704 /* (F_0_541 - F_1_847) */
#define F117_M196 -6436 /* (F_1_175 - F_1_961) */
#define F117_MF039 6437 /* (F_1_175 - F_0_390) */
#define F029_MF089 -4927 /* (F_0_298 - F_0_899) */
#define F150_MF089 4926 /* (F_1_501 - F_0_899) */
#define F205_MF256 -4176 /* (F_2_053 - F_2_562) */
#define F307_MF256 4177 /* (F_3_072 - F_2_562) */

#define CONST_BITS 13

#define PASS1_BITS  2
#define DESCALE_P1  11 /* (CONST_BITS - PASS1_BITS) */
#define DESCALE_P2  18 /* (CONST_BITS + PASS1_BITS + 3) */

#define PD_DESCALE_P1  1024 /* 1 << (DESCALE_P1 - 1) */
#define PD_DESCALE_P2  131072 /* 1 << (DESCALE_P2 - 1) */

#define CENTERJSAMPLE   128


#define SHFL_PUNPCKLBW  0,16,1,17,2,18,3,19,4,20,5,21,6,22,7,23
#define SHFL_PUNPCKHBW  8,24,9,25,10,26,11,27,12,28,13,29,14,30,15,31
#define SHFL_PUNPCKLWD  0,1,16,17,2,3,18,19,4,5,20,21,6,7,22,23
#define SHFL_PUNPCKHWD  8,9,24,25,10,11,26,27,12,13,28,29,14,15,30,31
#define SHFL_PUNPCKLDQ  0,1,2,3,16,17,18,19,4,5,6,7,20,21,22,23
#define SHFL_PUNPCKHDQ  8,9,10,11,24,25,26,27,12,13,14,15,28,29,30,31
#define SHFL_PUNPCKLQDQ 0,1,2,3,4,5,6,7,16,17,18,19,20,21,22,23
#define SHFL_PUNPCKHQDQ 8,9,10,11,12,13,14,15,24,25,26,27,28,29,30,31


    .text
#define xmm0 4
#define xmm1 5
#define xmm2 6
#define xmm3 7
#define xmm4 8
#define xmm5 9
#define xmm6 10
#define xmm7 11
#define wk0 12
#define wk1 13
#define wk2 14
#define wk3 15
#define wk4 16
#define wk5 17
#define wk6 18
#define wk7 19
#define wk8 20
#define wk9 21
#define wk10 22
#define wk11 23

#define quantptr 0 
#define inptr 1
#define output_buf 2
#define output_col 3

// b2..b1 = a1 * c1 + a2 * c2
// a2..a1 = a1 * c3 + a2 * c4
.macro matrix_dot_vec a1, a2, b1, b2, c1, c2, c3, c4
    local.get \a1
    local.get \a2
    v8x16.shuffle SHFL_PUNPCKLWD
    local.get \a1
    local.get \a2
    v8x16.shuffle 8,9,24,25,10,11,26,27,12,13,28,29,14,15,30,31
    local.set \a2
    local.set \a1

    local.get \a1
    v128.const \c1, \c2, \c1, \c2, \c1, \c2, \c1, \c2
    i32x4.dot_i16x8_s
    local.set \b1
    local.get \a2
    v128.const \c1, \c2, \c1, \c2, \c1, \c2, \c1, \c2
    i32x4.dot_i16x8_s
    local.set \b2
    local.get \a1
    v128.const \c3, \c4, \c3, \c4, \c3, \c4, \c3, \c4
    i32x4.dot_i16x8_s
    local.set \a1
    local.get \a2
    v128.const \c3, \c4, \c3, \c4, \c3, \c4, \c3, \c4
    i32x4.dot_i16x8_s
    local.set \a2
.endm

// a=a+b
// c=a-b
.macro add_sub_w a, b, c
    local.get \a
    local.get \a
    local.get \b
    i16x8.sub
    local.set \c
    local.get \b
    i16x8.add
    local.set \a
.endm

// a=a+b
// c=a-b
.macro add_sub_d a, b, c
    local.get \a
    local.get \a
    local.get \b
    i32x4.sub
    local.set \c
    local.get \b
    i32x4.add
    local.set \a
.endm

// a = (a + ad) >> sh [x4]
.macro round_sra_d_x4 a,b,c,d,tmp,sh,ad
    i32.const \ad
    i32x4.splat
    local.set \tmp

    local.get \a
    local.get \tmp
    i32x4.add
    i32.const \sh
    i32x4.shr_s
    local.set \a

    local.get \b
    local.get \tmp
    i32x4.add
    i32.const \sh
    i32x4.shr_s
    local.set \b

    local.get \c
    local.get \tmp
    i32x4.add
    i32.const \sh
    i32x4.shr_s
    local.set \c

    local.get \d
    local.get \tmp
    i32x4.add
    i32.const \sh
    i32x4.shr_s
    local.set \d
.endm

.macro store_row_mm ofs, src, lane
    local.get output_buf
    i32.load \ofs
    local.get output_col
    i32.add
    local.get \src
    i64x2.extract_lane \lane
    i64.store 0
.endm

asm_function jsimd_idct_islow_wasm (i32,i32,i32,i32) (i32)
    .local v128, v128, v128, v128, v128, v128, v128, v128, v128, v128, v128, v128, v128, v128, v128, v128, v128, v128, v128, v128

    block

    // -- Even part

    local.get inptr
    v128.load 0
    local.get quantptr
    v128.load 0
    i16x8.mul
    local.set xmm0
    local.get inptr
    v128.load 32
    local.get quantptr
    v128.load 32
    i16x8.mul
    local.set xmm1
    local.get inptr
    v128.load 64
    local.get quantptr
    v128.load 64
    i16x8.mul
    local.set xmm2
    local.get inptr
    v128.load 96
    local.get quantptr
    v128.load 96
    i16x8.mul
    local.set xmm3

    // (Original)
    // z1 = (z2 + z3) * 0.541196100;
    // tmp2 = z1 + z3 * -1.847759065;
    // tmp3 = z1 + z2 * 0.765366865;
    //
    // (This implementation)
    // tmp2 = z2 * 0.541196100 + z3 * (0.541196100 - 1.847759065);
    // tmp3 = z2 * (0.541196100 + 0.765366865) + z3 * 0.541196100;

    // xmm1=in2=z2, xmm3=in6=z3
    matrix_dot_vec xmm1, xmm3, xmm4, xmm5, F130_F054, F_0_541, F_0_541, F054_MF130
    // xmm4=tmp3L, xmm5=tmp3H, xmm1=tmp2L, xmm3=tmp2H

    add_sub_w  xmm0, xmm2, xmm6
    // xmm0=in0+in4,xmm6=in0-in4

    local.get xmm0
    i32x4.widen_low_i16x8_s
    i32.const CONST_BITS
    i32x4.shl
    local.set xmm7 // xmm7=tmp0L << CONST_BITS
    local.get xmm0
    i32x4.widen_high_i16x8_s
    i32.const CONST_BITS
    i32x4.shl
    local.set xmm2 // xmm2=tmp0H << CONST_BITS

    add_sub_d xmm7, xmm4, xmm0
    // xmm7=tmp10L, xmm0=tmp13L
    add_sub_d xmm2, xmm5, xmm4
    // xmm2=tmp10H, xmm4=tmp13H

    local.get xmm7
    local.set wk0   // wk(0)=tmp10L
    local.get xmm2
    local.set wk1   // wk(1)=tmp10H
    local.get xmm0
    local.set wk2   // wk(2)=tmp13L
    local.get xmm4
    local.set wk3   // wk(3)=tmp13H

    local.get xmm6
    i32x4.widen_low_i16x8_s
    i32.const CONST_BITS
    i32x4.shl
    local.set xmm5 // xmm7=tmp1L << CONST_BITS
    local.get xmm6
    i32x4.widen_high_i16x8_s
    i32.const CONST_BITS
    i32x4.shl
    local.set xmm7 // xmm7=tmp1H << CONST_BITS

    add_sub_d xmm5, xmm1, xmm2
    // xmm5=tmp11L, xmm2=tmp12L
    add_sub_d xmm7, xmm3, xmm0
    // xmm7=tmp11H, xmm0=tmp12H

    local.get xmm5
    local.set wk4   // wk(4)=tmp11L
    local.get xmm7
    local.set wk5   // wk(5)=tmp11H
    local.get xmm2
    local.set wk6   // wk(6)=tmp12L
    local.get xmm0
    local.set wk7   // wk(7)=tmp12H

    // -- Odd part

    local.get inptr
    v128.load 16
    local.get quantptr
    v128.load 16
    i16x8.mul
    local.set xmm4
    local.get inptr
    v128.load 48
    local.get quantptr
    v128.load 48
    i16x8.mul
    local.set xmm6
    local.get inptr
    v128.load 80
    local.get quantptr
    v128.load 80
    i16x8.mul
    local.set xmm1
    local.get inptr
    v128.load 112
    local.get quantptr
    v128.load 112
    i16x8.mul
    local.set xmm3

    local.get xmm6
    local.get xmm3
    i16x8.add
    local.set xmm5 // xmm5=z3
    local.get xmm4
    local.get xmm1
    i16x8.add
    local.set xmm7 // xmm7=z4

    // (Original)
    // z5 = (z3 + z4) * 1.175875602;
    // z3 = z3 * -1.961570560;  z4 = z4 * -0.390180644;
    // z3 += z5;  z4 += z5;
    //
    // (This implementation)
    // z3 = z3 * (1.175875602 - 1.961570560) + z4 * 1.175875602;
    // z4 = z3 * 1.175875602 + z4 * (1.175875602 - 0.390180644);

    matrix_dot_vec xmm5, xmm7, xmm2, xmm0, F117_M196, F_1_175, F_1_175, F117_MF039
    // xmm2=z3L, xmm0=z3H, xmm5=z4L, xmm7=z4H

    local.get xmm2
    local.set wk10  // wk(10)=z3L
    local.get xmm0
    local.set wk11  // wk(11)=z3H

    // (Original)
    // z1 = tmp0 + tmp3;  z2 = tmp1 + tmp2;
    // tmp0 = tmp0 * 0.298631336;  tmp1 = tmp1 * 2.053119869;
    // tmp2 = tmp2 * 3.072711026;  tmp3 = tmp3 * 1.501321110;
    // z1 = z1 * -0.899976223;  z2 = z2 * -2.562915447;
    // tmp0 += z1 + z3;  tmp1 += z2 + z4;
    // tmp2 += z2 + z3;  tmp3 += z1 + z4;
    //
    // (This implementation)
    // tmp0 = tmp0 * (0.298631336 - 0.899976223) + tmp3 * -0.899976223;
    // tmp1 = tmp1 * (2.053119869 - 2.562915447) + tmp2 * -2.562915447;
    // tmp2 = tmp1 * -2.562915447 + tmp2 * (3.072711026 - 2.562915447);
    // tmp3 = tmp0 * -0.899976223 + tmp3 * (1.501321110 - 0.899976223);
    // tmp0 += z3;  tmp1 += z4;
    // tmp2 += z3;  tmp3 += z4;

    matrix_dot_vec xmm3, xmm4, xmm2, xmm0, F029_MF089, -F_0_899, -F_0_899, F150_MF089
    // xmm2=tmp0L, xmm0=tmp0H, xmm3=tmp3L, xmm4=tmp3H

    local.get xmm2
    local.get wk10
    i32x4.add
    local.set xmm2  // xmm2=tmp0L
    local.get xmm0
    local.get wk11
    i32x4.add
    local.set xmm0  // xmm0=tmp0H
    local.get xmm3
    local.get xmm5
    i32x4.add
    local.set xmm3              // xmm3=tmp3L
    local.get xmm4
    local.get xmm7
    i32x4.add
    local.set xmm4              // xmm4=tmp3H

    local.get xmm2
    local.set wk8   // wk(8)=tmp0L
    local.get xmm0
    local.set wk9   // wk(9)=tmp0H

    matrix_dot_vec xmm1, xmm6, xmm2, xmm0, F205_MF256, -F_2_562, -F_2_562, F307_MF256
    // xmm2=tmp1L, xmm0=tmp1H, xmm1=tmp2L, xmm6=tmp2H

    local.get xmm2
    local.get xmm5
    i32x4.add
    local.set xmm2              // xmm2=tmp1L
    local.get xmm0
    local.get xmm7
    i32x4.add
    local.set xmm0              // xmm0=tmp1H
    local.get xmm1
    local.get wk10
    i32x4.add
    local.set xmm1  // xmm1=tmp2L
    local.get xmm6
    local.get wk11
    i32x4.add
    local.set xmm6  // xmm6=tmp2H

    local.get xmm2
    local.set wk10  // wk(10)=tmp1L
    local.get xmm0
    local.set wk11  // wk(11)=tmp1H

    // -- Final output stage

    local.get wk0
    local.set xmm5   // xmm5=tmp10L
    local.get wk1
    local.set xmm7   // xmm7=tmp10H

    add_sub_d xmm5, xmm3, xmm2
    // xmm5=data0L, xmm2=data7L
    add_sub_d xmm7, xmm4, xmm0
    // xmm7=data0H, xmm0=data7H

    round_sra_d_x4 xmm5, xmm7, xmm2, xmm0, xmm3, DESCALE_P1, PD_DESCALE_P1

    local.get xmm5
    local.get xmm7
    i16x8.narrow_i32x4_s
    local.set xmm5              // xmm5=data0=(00 01 02 03 04 05 06 07)
    local.get xmm2
    local.get xmm0
    i16x8.narrow_i32x4_s
    local.set xmm2              // xmm2=data7=(70 71 72 73 74 75 76 77)

    local.get wk4
    local.set xmm4   // xmm4=tmp11L
    local.get wk5
    local.set xmm3   // xmm3=tmp11H

    add_sub_d xmm4, xmm1, xmm7
    // xmm4=data1L, xmm7=data6L
    add_sub_d xmm3, xmm6, xmm0
    // xmm7=data1H, xmm0=data6H

    round_sra_d_x4 xmm4, xmm3, xmm7, xmm0, xmm1, DESCALE_P1, PD_DESCALE_P1

    local.get xmm4
    local.get xmm3
    i16x8.narrow_i32x4_s
    local.set xmm4              // xmm4=data1=(10 11 12 13 14 15 16 17)
    local.get xmm7
    local.get xmm0
    i16x8.narrow_i32x4_s
    local.set xmm7              // xmm7=data6=(60 61 62 63 64 65 66 67)

    // transpose coefficients(phase 1)
    local.get xmm5
    local.get xmm4
    v8x16.shuffle SHFL_PUNPCKLWD
    local.get xmm5
    local.get xmm4
    v8x16.shuffle SHFL_PUNPCKHWD
    local.set xmm6  // xmm6=(04 14 05 15 06 16 07 17)
    local.set xmm5  // xmm5=(00 10 01 11 02 12 03 13)
    local.get xmm7
    local.get xmm2
    v8x16.shuffle SHFL_PUNPCKLWD
    local.get xmm7
    local.get xmm2
    v8x16.shuffle SHFL_PUNPCKHWD
    local.set xmm1  // xmm1=(64 74 65 75 66 76 67 77)
    local.set xmm7  // xmm7=(60 70 61 71 62 72 63 73)

    local.get wk6
    local.set xmm3   // xmm3=tmp12L
    local.get wk7
    local.set xmm0   // xmm0=tmp12H
    local.get wk10
    local.set xmm4  // xmm4=tmp1L
    local.get wk11
    local.set xmm2  // xmm2=tmp1H

    local.get xmm5
    local.set wk0   // wk(0)=(00 10 01 11 02 12 03 13)
    local.get xmm6
    local.set wk1   // wk(1)=(04 14 05 15 06 16 07 17)
    local.get xmm7
    local.set wk4   // wk(4)=(60 70 61 71 62 72 63 73)
    local.get xmm1
    local.set wk5   // wk(5)=(64 74 65 75 66 76 67 77)

    add_sub_d xmm3, xmm4, xmm5
    // xmm3=data2L, xmm5=data5L
    add_sub_d xmm0, xmm2, xmm6
    // xmm0=data2H, xmm6=data5H

    round_sra_d_x4 xmm3, xmm0, xmm5, xmm6, xmm7, DESCALE_P1, PD_DESCALE_P1

    local.get xmm3
    local.get xmm0
    i16x8.narrow_i32x4_s
    local.set xmm3              // xmm3=data2=(20 21 22 23 24 25 26 27)
    local.get xmm5
    local.get xmm6
    i16x8.narrow_i32x4_s
    local.set xmm5              // xmm5=data5=(50 51 52 53 54 55 56 57)

    local.get wk2
    local.set xmm1   // xmm1=tmp13L
    local.get wk3
    local.set xmm4   // xmm4=tmp13H
    local.get wk8
    local.set xmm2   // xmm2=tmp0L
    local.get wk9
    local.set xmm7   // xmm7=tmp0H

    add_sub_d xmm1, xmm2, xmm0
    // xmm1=data3L, xmm0=data4L
    add_sub_d xmm4, xmm7, xmm6
    // xmm4=data3H, xmm6=data4H

    round_sra_d_x4 xmm1, xmm4, xmm0, xmm6, xmm2, DESCALE_P1, PD_DESCALE_P1

    local.get xmm1
    local.get xmm4
    i16x8.narrow_i32x4_s
    local.set xmm1             // xmm1=data3=(30 31 32 33 34 35 36 37)
    local.get xmm0
    local.get xmm6
    i16x8.narrow_i32x4_s
    local.set xmm0              // xmm0=data4=(40 41 42 43 44 45 46 47)

    local.get wk0
    local.set xmm7   // xmm7=(00 10 01 11 02 12 03 13)
    local.get wk1
    local.set xmm2   // xmm2=(04 14 05 15 06 16 07 17)

    // transpose coefficients(phase 1)
    local.get xmm3
    local.get xmm1
    v8x16.shuffle SHFL_PUNPCKLWD
    local.get xmm3
    local.get xmm1
    v8x16.shuffle SHFL_PUNPCKHWD
    local.set xmm4  // xmm4=(24 34 25 35 26 36 27 37)
    local.set xmm3  // xmm3=(20 30 21 31 22 32 23 33)
    local.get xmm0
    local.get xmm5
    v8x16.shuffle SHFL_PUNPCKLWD
    local.get xmm0
    local.get xmm5
    v8x16.shuffle SHFL_PUNPCKHWD
    local.set xmm6  // xmm6=(44 54 45 55 46 56 47 57)
    local.set xmm0  // xmm0=(40 50 41 51 42 52 43 53)

    // transpose coefficients(phase 2)
    local.get xmm7
    local.get xmm3
    v8x16.shuffle SHFL_PUNPCKLDQ
    local.get xmm7
    local.get xmm3
    v8x16.shuffle SHFL_PUNPCKHDQ
    local.set xmm1 // xmm1=(02 12 22 32 03 13 23 33)
    local.set xmm7 // xmm7=(00 10 20 30 01 11 21 31)
    local.get xmm2
    local.get xmm4
    v8x16.shuffle SHFL_PUNPCKLDQ
    local.get xmm2
    local.get xmm4
    v8x16.shuffle SHFL_PUNPCKHDQ
    local.set xmm5 // xmm5=(06 16 26 36 07 17 27 37)
    local.set xmm2 // xmm2=(04 14 24 34 05 15 25 35)

    local.get wk4
    local.set xmm3   // xmm3=(60 70 61 71 62 72 63 73)
    local.get wk5
    local.set xmm4   // xmm4=(64 74 65 75 66 76 67 77)

    local.get xmm2
    local.set wk6   // wk(6)=(04 14 24 34 05 15 25 35)
    local.get xmm5
    local.set wk7   // wk(7)=(06 16 26 36 07 17 27 37)

    // transpose coefficients(phase 2)
    local.get xmm0
    local.get xmm3
    v8x16.shuffle SHFL_PUNPCKLDQ
    local.get xmm0
    local.get xmm3
    v8x16.shuffle SHFL_PUNPCKHDQ
    local.set xmm2 // xmm2=(42 52 62 72 43 53 63 73)
    local.set xmm0 // xmm0=(40 50 60 70 41 51 61 71)
    local.get xmm6
    local.get xmm4
    v8x16.shuffle SHFL_PUNPCKLDQ
    local.get xmm6
    local.get xmm4
    v8x16.shuffle SHFL_PUNPCKHDQ
    local.set xmm5 // xmm5=(46 56 66 76 47 57 67 77)
    local.set xmm6 // xmm6=(44 54 64 74 45 55 65 75)

    // transpose coefficients(phase 3)
    local.get xmm7
    local.get xmm0
    v8x16.shuffle SHFL_PUNPCKLQDQ
    local.get xmm7
    local.get xmm0
    v8x16.shuffle SHFL_PUNPCKHQDQ
    local.set xmm3 // xmm3=col1=(01 11 21 31 41 51 61 71)
    local.set xmm7 // xmm7=col0=(00 10 20 30 40 50 60 70)
    local.get xmm1
    local.get xmm2
    v8x16.shuffle SHFL_PUNPCKLQDQ
    local.get xmm1
    local.get xmm2
    v8x16.shuffle SHFL_PUNPCKHQDQ
    local.set xmm4 // xmm4=col3=(03 13 23 33 43 53 63 73)
    local.set xmm1 // xmm1=col2=(02 12 22 32 42 52 62 72)

    local.get wk6
    local.set xmm0   // xmm0=(04 14 24 34 05 15 25 35)
    local.get wk7
    local.set xmm2   // xmm2=(06 16 26 36 07 17 27 37)

    local.get xmm3
    local.set wk8   // wk(8)=col1
    local.get xmm4
    local.set wk9   // wk(9)=col3

    // transpose coefficients(phase 3)
    local.get xmm0
    local.get xmm6
    v8x16.shuffle SHFL_PUNPCKLQDQ
    local.get xmm0
    local.get xmm6
    v8x16.shuffle SHFL_PUNPCKHQDQ
    local.set xmm3 // xmm3=col5=(05 15 25 35 45 55 65 75)
    local.set xmm0 // xmm0=col4=(04 14 24 34 44 54 64 74)
    local.get xmm2
    local.get xmm5
    v8x16.shuffle SHFL_PUNPCKLQDQ
    local.get xmm2
    local.get xmm5
    v8x16.shuffle SHFL_PUNPCKHQDQ
    local.set xmm4 // xmm4=col7=(07 17 27 37 47 57 67 77)
    local.set xmm2 // xmm2=col6=(06 16 26 36 46 56 66 76)

    local.get xmm3
    local.set wk10  // wk(10)=col5
    local.get xmm4
    local.set wk11  // wk(11)=col7

    end_block // .column_end:

    // ---- Pass 2: process rows from work array, store into output array.

    // -- Even part

    // xmm7=col0, xmm1=col2, xmm0=col4, xmm2=col6

    // (Original)
    // z1 = (z2 + z3) * 0.541196100;
    // tmp2 = z1 + z3 * -1.847759065;
    // tmp3 = z1 + z2 * 0.765366865;
    //
    // (This implementation)
    // tmp2 = z2 * 0.541196100 + z3 * (0.541196100 - 1.847759065);
    // tmp3 = z2 * (0.541196100 + 0.765366865) + z3 * 0.541196100;

    // xmm1=in2=z2,xmm2=in6=z3
    matrix_dot_vec xmm1, xmm2, xmm6, xmm5, F130_F054, F_0_541, F_0_541, F054_MF130
    // xmm6=tmp3L, xmm5=tmp3H, xmm1=tmp2L, xmm2=tmp2H

    add_sub_w xmm7, xmm0, xmm3
    // xmm7=in0+in4, xmm3=in0-in4

    local.get xmm7
    i32x4.widen_low_i16x8_s
    i32.const CONST_BITS
    i32x4.shl
    local.set xmm4 // xmm4=tmp0L << CONST_BITS
    local.get xmm7
    i32x4.widen_high_i16x8_s
    i32.const CONST_BITS
    i32x4.shl
    local.set xmm0 // xmm0=tmp0H << CONST_BITS

    add_sub_d xmm4, xmm6, xmm7
    // xmm4=tmp10L, xmm7=tmp13L
    add_sub_d xmm0, xmm5, xmm6
    // xmm0=tmp10H, xmm6=tmp13H

    local.get xmm4
    local.set wk0   // wk(0)=tmp10L
    local.get xmm0
    local.set wk1   // wk(1)=tmp10H
    local.get xmm7
    local.set wk2   // wk(2)=tmp13L
    local.get xmm6
    local.set wk3   // wk(3)=tmp13H

    local.get xmm3
    i32x4.widen_low_i16x8_s
    i32.const CONST_BITS
    i32x4.shl
    local.set xmm5 // xmm5=tmp1L << CONST_BITS
    local.get xmm3
    i32x4.widen_high_i16x8_s
    i32.const CONST_BITS
    i32x4.shl
    local.set xmm4 // xmm4=tmp1H << CONST_BITS

    add_sub_d xmm5, xmm1, xmm0
    // xmm5=tmp11L, xmm0=tmp12L
    add_sub_d xmm4, xmm2, xmm7
    // xmm4=tmp11H, xmm7=tmp12H

    local.get xmm5
    local.set wk4   // wk(4)=tmp11L
    local.get xmm4
    local.set wk5   // wk(5)=tmp11H
    local.get xmm0
    local.set wk6   // wk(6)=tmp12L
    local.get xmm7
    local.set wk7   // wk(7)=tmp12H

    // -- Odd part

    local.get wk9
    local.set xmm6   // xmm6=col3
    local.get wk8
    local.set xmm3   // xmm3=col1
    local.get wk11
    local.set xmm1  // xmm1=col7
    local.get wk10
    local.set xmm2  // xmm2=col5

    local.get xmm6
    local.get xmm1
    i16x8.add
    local.set xmm5 // xmm5=z3
    local.get xmm3
    local.get xmm2
    i16x8.add
    local.set xmm4 // xmm4=z4

    // (Original)
    // z5 = (z3 + z4) * 1.175875602;
    // z3 = z3 * -1.961570560;  z4 = z4 * -0.390180644;
    // z3 += z5;  z4 += z5;
    //
    // (This implementation)
    // z3 = z3 * (1.175875602 - 1.961570560) + z4 * 1.175875602;
    // z4 = z3 * 1.175875602 + z4 * (1.175875602 - 0.390180644);

    matrix_dot_vec xmm5, xmm4, xmm0, xmm7, F117_M196, F_1_175, F_1_175, F117_MF039
    //  xmm0=z3L, xmm7=z3H, xmm5=z4L, xmm4=z4H

    local.get xmm0
    local.set wk10  // wk(10)=z3L
    local.get xmm7
    local.set wk11  // wk(11)=z3H

    // (Original)
    // z1 = tmp0 + tmp3;  z2 = tmp1 + tmp2;
    // tmp0 = tmp0 * 0.298631336;  tmp1 = tmp1 * 2.053119869;
    // tmp2 = tmp2 * 3.072711026;  tmp3 = tmp3 * 1.501321110;
    // z1 = z1 * -0.899976223;  z2 = z2 * -2.562915447;
    // tmp0 += z1 + z3;  tmp1 += z2 + z4;
    // tmp2 += z2 + z3;  tmp3 += z1 + z4;
    //
    // (This implementation)
    // tmp0 = tmp0 * (0.298631336 - 0.899976223) + tmp3 * -0.899976223;
    // tmp1 = tmp1 * (2.053119869 - 2.562915447) + tmp2 * -2.562915447;
    // tmp2 = tmp1 * -2.562915447 + tmp2 * (3.072711026 - 2.562915447);
    // tmp3 = tmp0 * -0.899976223 + tmp3 * (1.501321110 - 0.899976223);
    // tmp0 += z3;  tmp1 += z4;
    // tmp2 += z3;  tmp3 += z4;

    matrix_dot_vec xmm1, xmm3, xmm0, xmm7, F029_MF089, -F_0_899, -F_0_899, F150_MF089
    //  xmm0=z3L, xmm7=z3H, xmm5=z4L, xmm4=z4H

    local.get xmm0
    local.get wk10
    i32x4.add
    local.set xmm0  // xmm0=tmp0L
    local.get xmm7
    local.get wk11
    i32x4.add
    local.set xmm7  // xmm7=tmp0H
    local.get xmm1
    local.get xmm5
    i32x4.add
    local.set xmm1              // xmm1=tmp3L
    local.get xmm3
    local.get xmm4
    i32x4.add
    local.set xmm3              // xmm3=tmp3H

    local.get xmm0
    local.set wk8   // wk(8)=tmp0L
    local.get xmm7
    local.set wk9   // wk(9)=tmp0H

    matrix_dot_vec xmm2, xmm6, xmm0, xmm7, F205_MF256, -F_2_562, -F_2_562, F307_MF256
    // xmm0=tmp1L, xmm7=tmp1H, xmm2=tmp2L, xmm6=tmp2H

    local.get xmm0
    local.get xmm5
    i32x4.add
    local.set xmm0              // xmm0=tmp1L
    local.get xmm7
    local.get xmm4
    i32x4.add
    local.set xmm7              // xmm7=tmp1H
    local.get xmm2
    local.get wk10
    i32x4.add
    local.set xmm2  // xmm2=tmp2L
    local.get xmm6
    local.get wk11
    i32x4.add
    local.set xmm6  // xmm6=tmp2H

    local.get xmm0
    local.set wk10  // wk(10)=tmp1L
    local.get xmm7
    local.set wk11  // wk(11)=tmp1H

    // -- Final output stage

    local.get wk0
    local.set xmm5   // xmm5=tmp10L
    local.get wk1
    local.set xmm4   // xmm4=tmp10H

    add_sub_d xmm5, xmm1, xmm0
    // xmm5=data0L, xmm0=data7L
    add_sub_d xmm4, xmm3, xmm7
    // xmm4=data0H, xmm7=data7H

    round_sra_d_x4 xmm5, xmm4, xmm0, xmm7, xmm1, DESCALE_P2, PD_DESCALE_P2

    local.get xmm5
    local.get xmm4
    i16x8.narrow_i32x4_s
    local.set xmm5             // xmm5=data0=(00 10 20 30 40 50 60 70)
    local.get xmm0
    local.get xmm7
    i16x8.narrow_i32x4_s
    local.set xmm0              // xmm0=data7=(07 17 27 37 47 57 67 77)

    local.get wk4
    local.set xmm3   // xmm3=tmp11L
    local.get wk5
    local.set xmm1   // xmm1=tmp11H

    add_sub_d xmm3, xmm2, xmm4
    // xmm3=data1L, xmm4=data6L
    add_sub_d xmm1, xmm6, xmm7
    // xmm1=data1H, xmm7=data6H

    round_sra_d_x4 xmm3, xmm1, xmm4, xmm7, xmm2, DESCALE_P2, PD_DESCALE_P2

    local.get xmm3
    local.get xmm1
    i16x8.narrow_i32x4_s
    local.set xmm3             // xmm3=data1=(01 11 21 31 41 51 61 71)
    local.get xmm4
    local.get xmm7
    i16x8.narrow_i32x4_s
    local.set xmm4              // xmm4=data6=(06 16 26 36 46 56 66 76)

    local.get xmm5
    local.get xmm4
    i8x16.narrow_i16x8_s
    local.set xmm5              // xmm5=(00 10 20 30 40 50 60 70 06 16 26 36 46 56 66 76)
    local.get xmm3
    local.get xmm0
    i8x16.narrow_i16x8_s
    local.set xmm3              // xmm3=(01 11 21 31 41 51 61 71 07 17 27 37 47 57 67 77)

    local.get wk6
    local.set xmm6   // xmm6=tmp12L
    local.get wk7
    local.set xmm2   // xmm2=tmp12H
    local.get wk10
    local.set xmm1  // xmm1=tmp1L
    local.get wk11
    local.set xmm7  // xmm7=tmp1H

    local.get xmm5
    local.set wk0   // wk(0)=(00 10 20 30 40 50 60 70 06 16 26 36 46 56 66 76)
    local.get xmm3
    local.set wk1   // wk(1)=(01 11 21 31 41 51 61 71 07 17 27 37 47 57 67 77)

    add_sub_d xmm6, xmm1, xmm4
    // xmm6=data2L, xmm4=data5L
    add_sub_d xmm2, xmm7, xmm0
    // xmm2=data2H, xmm0=data5H

    round_sra_d_x4 xmm6, xmm2, xmm4, xmm0, xmm5, DESCALE_P2, PD_DESCALE_P2

    local.get xmm6
    local.get xmm2
    i16x8.narrow_i32x4_s
    local.set xmm6             // xmm6=data2=(02 12 22 32 42 52 62 72)
    local.get xmm4
    local.get xmm0
    i16x8.narrow_i32x4_s
    local.set xmm4              // xmm4=data5=(05 15 25 35 45 55 65 75)

    local.get wk2
    local.set xmm3   // xmm3=tmp13L
    local.get wk3
    local.set xmm1   // xmm1=tmp13H
    local.get wk8
    local.set xmm7   // xmm7=tmp0L
    local.get wk9
    local.set xmm5   // xmm5=tmp0H

    add_sub_d xmm3, xmm7, xmm2
    // xmm3=data3L, xmm2=data4L
    add_sub_d xmm1, xmm5, xmm0
    // xmm1=data3H, xmm0=data4H

    round_sra_d_x4 xmm3, xmm1, xmm2, xmm0, xmm7, DESCALE_P2, PD_DESCALE_P2

    i32.const   CENTERJSAMPLE
    i8x16.splat
    local.set   xmm5

    local.get xmm3
    local.get xmm1
    i16x8.narrow_i32x4_s
    local.set xmm3             // xmm3=data3=(03 13 23 33 43 53 63 73)
    local.get xmm2
    local.get xmm0
    i16x8.narrow_i32x4_s
    local.set xmm2              // xmm2=data4=(04 14 24 34 44 54 64 74)

    local.get wk0
    local.set xmm7  // xmm7=(00 10 20 30 40 50 60 70 06 16 26 36 46 56 66 76)
    local.get wk1
    local.set xmm1  // xmm1=(01 11 21 31 41 51 61 71 07 17 27 37 47 57 67 77)

    local.get xmm6
    local.get xmm2
    i8x16.narrow_i16x8_s
    local.set xmm6              // xmm6=(02 12 22 32 42 52 62 72 04 14 24 34 44 54 64 74)
    local.get xmm3
    local.get xmm4
    i8x16.narrow_i16x8_s
    local.set xmm3              // xmm3=(03 13 23 33 43 53 63 73 05 15 25 35 45 55 65 75)

    local.get xmm7
    local.get xmm5
    i8x16.add
    local.set xmm7
    local.get xmm1
    local.get xmm5
    i8x16.add
    local.set xmm1
    local.get xmm6
    local.get xmm5
    i8x16.add
    local.set xmm6
    local.get xmm3
    local.get xmm5
    i8x16.add
    local.set xmm3

    // transpose coefficients(phase 1)
    local.get xmm7
    local.get xmm1
    v8x16.shuffle SHFL_PUNPCKLBW
    local.set xmm0    // (00 01 10 11 20 21 30 31 40 41 50 51 60 61 70 71)
    local.get xmm7
    local.get xmm1
    v8x16.shuffle SHFL_PUNPCKHBW
    local.set xmm2    // (06 07 16 17 26 27 36 37 46 47 56 57 66 67 76 77)
    local.get xmm6
    local.get xmm3
    v8x16.shuffle SHFL_PUNPCKLBW
    local.set xmm4    // (02 03 12 13 22 23 32 33 42 43 52 53 62 63 72 73)
    local.get xmm6
    local.get xmm3
    v8x16.shuffle SHFL_PUNPCKHBW
    local.set xmm5    // (04 05 14 15 24 25 34 35 44 45 54 55 64 65 74 75)

    // transpose coefficients(phase 2)
    local.get xmm0
    local.get xmm4
    v8x16.shuffle SHFL_PUNPCKLWD
    local.set xmm7   // (00 01 02 03 10 11 12 13 20 21 22 23 30 31 32 33)
    local.get xmm0
    local.get xmm4
    v8x16.shuffle SHFL_PUNPCKHWD
    local.set xmm1   // (40 41 42 43 50 51 52 53 60 61 62 63 70 71 72 73)
    local.get xmm5
    local.get xmm2
    v8x16.shuffle SHFL_PUNPCKLWD
    local.set xmm6   // (04 05 06 07 14 15 16 17 24 25 26 27 34 35 36 37)
    local.get xmm5
    local.get xmm2
    v8x16.shuffle SHFL_PUNPCKHWD
    local.set xmm3   // (44 45 46 47 54 55 56 57 64 65 66 67 74 75 76 77)

    // transpose coefficients(phase 3)
    local.get xmm7
    local.get xmm6
    v8x16.shuffle SHFL_PUNPCKLDQ
    local.set xmm0 // (00 01 02 03 04 05 06 07 10 11 12 13 14 15 16 17)
    local.get xmm7
    local.get xmm6
    v8x16.shuffle SHFL_PUNPCKHDQ
    local.set xmm2 // (20 21 22 23 24 25 26 27 30 31 32 33 34 35 36 37)
    local.get xmm1
    local.get xmm3
    v8x16.shuffle SHFL_PUNPCKLDQ
    local.set xmm4 // (40 41 42 43 44 45 46 47 50 51 52 53 54 55 56 57)
    local.get xmm1
    local.get xmm3
    v8x16.shuffle SHFL_PUNPCKHDQ
    local.set xmm5 // (60 61 62 63 64 65 66 67 70 71 72 73 74 75 76 77)

    store_row_mm 0, xmm0, 0
    store_row_mm 8, xmm2, 0
    store_row_mm 16, xmm4, 0
    store_row_mm 24, xmm5, 0

    store_row_mm 4, xmm0, 1
    store_row_mm 12, xmm2, 1
    store_row_mm 20, xmm4, 1
    store_row_mm 28, xmm5, 1

    i32.const 0
    end_function

asm_function jsimd_extrgb_ycc_convert_wasm (i32,i32,i32,i32,i32) ()
    unreachable
    end_function

asm_function jsimd_ycc_extrgb_convert_wasm (i32,i32,i32,i32,i32) ()
    unreachable
    end_function

asm_function jsimd_ycc_rgb565_convert_wasm (i32,i32,i32,i32,i32) ()
    unreachable
    end_function

asm_function jsimd_h2v1_fancy_upsample_wasm (i32,i32,i32,i32) (i32)
    unreachable
    end_function

asm_function jsimd_idct_2x2_wasm (i32,i32,i32,i32) (i32)
    unreachable
    end_function

asm_function jsimd_idct_4x4_wasm (i32,i32,i32,i32) (i32)
    unreachable
    end_function

asm_function jsimd_idct_ifast_wasm (i32,i32,i32,i32) (i32)
    unreachable
    end_function

asm_function jsimd_ycc_extrgbx_convert_wasm (i32,i32,i32,i32,i32) ()
    unreachable
    end_function

asm_function jsimd_ycc_extbgr_convert_wasm (i32,i32,i32,i32,i32) ()
    unreachable
    end_function

asm_function jsimd_ycc_extbgrx_convert_wasm (i32,i32,i32,i32,i32) ()
    unreachable
    end_function

asm_function jsimd_ycc_extxbgr_convert_wasm (i32,i32,i32,i32,i32) ()
    unreachable
    end_function

asm_function jsimd_ycc_extxrgb_convert_wasm (i32,i32,i32,i32,i32) ()
    unreachable
    end_function


.globaltype __stack_pointer, i32
