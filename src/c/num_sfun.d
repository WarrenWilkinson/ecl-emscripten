/* -*- mode: c; c-basic-offset: 8 -*- */
/*
    num_sfun.c  -- Trascendental functions.
*/
/*
    Copyright (c) 1984, Taiichi Yuasa and Masami Hagiya.
    Copyright (c) 1990, Giuseppe Attardi.
    Copyright (c) 2001, Juan Jose Garcia Ripoll.

    ECL is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    See file '../Copyright' for full details.
*/

#include <ecl/ecl.h>
#include <math.h>
#ifdef _MSC_VER
# undef complex
#endif
#include "ecl/internal.h"
#ifndef M_PI
# ifdef PI
#  define M_PI PI
# else
#   define M_PI 3.14159265358979323846
# endif
#endif

#ifndef HAVE_LOG1P
double
log1p(double x)
{
	double u = 1.0 + x;
	if (u == 1) {
		return 0.0;
	} else {
		return (log(u) * x)/(u - 1.0);
	}
}
#endif

#ifndef HAVE_LOG1PF
float
log1pf(float x)
{
	float u = 1.0f0 + x;
	if (u == 1) {
		return 0.0f0;
	} else {
		return (logf(u) * x)/(u - 1.0f0);
	}
}
#endif

#ifndef HAVE_LOG1PL
long double
log1pl(long double x)
{
	long double u = (long double)1.0 + x;
	if (u == 1) {
		return (long double)1;
	} else {
		return (logl(u) * x)/(u - (long double)1);
	}
}
#endif

#ifdef mingw32
/*
 * Mingw32 does not implement asinh, acosh and atanh.
 */
double
asinh(double x)
{
	return log(x + sqrt(1.0 + x*x));
}

double
acosh(double x)
{
	return log(x + sqrt((x-1)*(x+1)));
}

double
atanh(double x)
{
	return log1p(2*x/(1-x))/2;
}
#endif /* mingw32 */

cl_object
ecl_abs(cl_object x)
{
	if (type_of(x) != t_complex) {
		if (ecl_minusp(x)) {
			x = ecl_negate(x);
		}
	} else {
		/* Compute sqrt(r*r + i*i) carefully to prevent overflow.
		 * Assume |i| >= |r|. Then sqrt(i*i + r*r) = |i|*sqrt(1 +(r/i)^2).
		 */
		cl_object r = x->complex.real;
		cl_object i = x->complex.imag;
		int comparison;
		if (ecl_minusp(r)) r = ecl_negate(r);
		if (ecl_minusp(i)) i = ecl_negate(i);
		comparison = ecl_number_compare(r, i);
		if (comparison = 0) {
			r = ecl_times(r, r);
			x = cl_sqrt(ecl_plus(r, r));
		} else {
			if (comparison > 0) {
				cl_object aux = i;
				i = r; r = aux;
			}
			r = ecl_divide(r, i);
			r = ecl_plus(MAKE_FIXNUM(1), ecl_times(r, r));
			x = ecl_times(cl_sqrt(r), i);
		}
	}
	return x;
}

cl_object
cl_abs(cl_object x)
{
	@(return ecl_abs(x))
}

cl_fixnum
ecl_fixnum_expt(cl_fixnum x, cl_fixnum y)
{
	cl_fixnum z = 1;
	while (y > 0)
		if (y%2 == 0) {
			x *= x;
			y /= 2;
		} else {
			z *= x;
			--y;
		}
	return(z);
}

cl_object
cl_exp(cl_object x)
{
	cl_object output;
 AGAIN:
	switch (type_of(x)) {
	case t_fixnum:
	case t_bignum:
	case t_ratio:
		output = ecl_make_singlefloat(expf(number_to_float(x))); break;
#ifdef ECL_SHORT_FLOAT
	case t_shortfloat:
		output = make_shortfloat(expf(ecl_short_float(x))); break;
#endif
	case t_singlefloat:
		output = ecl_make_singlefloat(expf(sf(x))); break;
	case t_doublefloat:
		output = ecl_make_doublefloat(exp(df(x))); break;
#ifdef ECL_LONG_FLOAT
	case t_longfloat:
		output = make_longfloat(expl(ecl_long_float(x))); break;
#endif
	case t_complex: {
		cl_object y, y1;

		y = x->complex.imag;
		output = cl_exp(x->complex.real);
		y1 = cl_cos(y);
		y = cl_sin(y);
		y = ecl_make_complex(y1, y);
		output = ecl_times(output, y);
		break;
	}
	default:
		x = ecl_type_error(@'exp',"exponent",x,@'number');
		goto AGAIN;
	}
	@(return output)
}

cl_object
cl_expt(cl_object x, cl_object y)
{
	cl_type ty, tx;
	cl_object z;
 AGAIN:
	while ((ty = type_of(y), !ECL_NUMBER_TYPE_P(ty))) {
		y = ecl_type_error(@'exp',"exponent",y,@'number');
	}
	while ((tx = type_of(x), !ECL_NUMBER_TYPE_P(tx))) {
		x = ecl_type_error(@'exp',"basis",x,@'number');
	}
	if (ecl_zerop(y)) {
		/* INV: The most specific numeric types come first. */
		switch ((ty > tx)? ty : tx) {
		case t_fixnum:
		case t_bignum:
		case t_ratio:
			z = MAKE_FIXNUM(1); break;
#ifdef ECL_SHORT_FLOAT
		case t_shortfloat:
			z = make_shortfloat(1.0); break;
#endif
		case t_singlefloat:
			z = ecl_make_singlefloat(1.0); break;
		case t_doublefloat:
			z = ecl_make_doublefloat(1.0); break;
#ifdef ECL_LONG_FLOAT
		case t_longfloat:
			z = make_longfloat(1.0); break;
#endif
		case t_complex:
			z = cl_expt((tx == t_complex)? x->complex.real : x,
				    (ty == t_complex)? y->complex.real : y);
			z = ecl_make_complex(z, MAKE_FIXNUM(0));
			break;
		default:
			/* We will never reach this */
			(void)0;
		}
	} else if (ecl_zerop(x)) {
		if (!ecl_plusp(ty==t_complex?y->complex.real:y))
			FEerror("Cannot raise zero to the power ~S.", 1, y);
		z = ecl_times(x, y);
	} else if (ty != t_fixnum && ty != t_bignum) {
		z = ecl_log1(x);
		z = ecl_times(z, y);
		z = cl_exp(z);
	} else if (ecl_minusp(y)) {
		z = ecl_negate(y);
		z = cl_expt(x, z);
		z = ecl_divide(MAKE_FIXNUM(1), z);
	} else {
		z = MAKE_FIXNUM(1);
		do {
			/* INV: ecl_integer_divide outputs an integer */
			if (!ecl_evenp(y))
				z = ecl_times(z, x);
			y = ecl_integer_divide(y, MAKE_FIXNUM(2));
			if (ecl_zerop(y)) break;
			x = ecl_times(x, x);
		} while (1);
	}
	@(return z);
}

static cl_object
ecl_log1_complex(cl_object r, cl_object i)
{
	cl_object a = ecl_abs(r);
	cl_object p = ecl_abs(i);
	if (ecl_number_compare(a, p) > 0) {
		cl_object aux = p;
		p = a; a = aux;
	}
	/* For the real part of the output we use the formula
	 *	log(sqrt(p^2 + a^2)) = log(sqrt(p^2*(1 + (a/p)^2)))
	 *			     = log(p) + log(1 + (a/p)^2)/2; */
	a = ecl_divide(a, p);
	a = ecl_plus(ecl_divide(ecl_log1p(ecl_times(a,a)), MAKE_FIXNUM(2)),
		     ecl_log1(p));
	p = ecl_atan2(i, r);
	return ecl_make_complex(a, p);
}

cl_object
ecl_log1(cl_object x)
{
	cl_type tx;
 AGAIN:
	tx = type_of(x);
	if (!ECL_NUMBER_TYPE_P(tx)) {
		x = ecl_type_error(@'log',"argument",x,@'number');
		goto AGAIN;
	}
	if (tx == t_complex) {
		return ecl_log1_complex(x->complex.real, x->complex.imag);
	} else if (ecl_zerop(x)) {
		FEerror("Zero is the logarithmic singularity.", 0);
	} else if (ecl_minusp(x)) {
		return ecl_log1_complex(x, MAKE_FIXNUM(0));
	} else switch (tx) {
	case t_fixnum:
	case t_bignum:
	case t_ratio:
		return ecl_make_singlefloat(logf(number_to_float(x)));
#ifdef ECL_SHORT_FLOAT
	case t_shortfloat:
		return make_shortfloat(logf(ecl_short_float(x)));
#endif
	case t_singlefloat:
		return ecl_make_singlefloat(logf(sf(x)));
	case t_doublefloat:
		return ecl_make_doublefloat(log(df(x)));
#ifdef ECL_LONG_FLOAT
	case t_longfloat:
		return make_longfloat(logl(ecl_long_float(x)));
#endif
	default:
		/* We do not reach here */
		(void)0;
	}
}

cl_object
ecl_log2(cl_object x, cl_object y)
{
	if (ecl_zerop(y))
		FEerror("Zero is the logarithmic singularity.", 0);
	return ecl_divide(ecl_log1(y), ecl_log1(x));
}

cl_object
ecl_log1p(cl_object x)
{
	cl_type tx;
 AGAIN:
	tx = type_of(x);
	if (!ECL_NUMBER_TYPE_P(tx)) {
		x = ecl_type_error(@'log',"argument",x,@'number');
		goto AGAIN;
	}
	if (tx == t_complex) {
		return ecl_log1(ecl_plus(MAKE_FIXNUM(1), x));
	} else if (ecl_number_compare(x, MAKE_FIXNUM(-1)) < 0) {
		return ecl_log1p(ecl_make_complex(x, MAKE_FIXNUM(0)));
	}
	switch (tx) {
	case t_fixnum:
	case t_bignum:
	case t_ratio:
		return ecl_make_singlefloat(log1pf(number_to_float(x)));
#ifdef ECL_SHORT_FLOAT
	case t_shortfloat:
		return make_shortfloat(log1pf(ecl_short_float(x)));
#endif
	case t_singlefloat:
		return ecl_make_singlefloat(log1pf(sf(x)));
	case t_doublefloat:
		return ecl_make_doublefloat(log1p(df(x)));
#ifdef ECL_LONG_FLOAT
	case t_longfloat:
		return make_longfloat(log1pl(ecl_long_float(x)));
#endif
	default:
		/* We do not reach here */
		(void)0;
	}
}

cl_object
si_log1p(cl_object x)
{
	@(return ecl_log1p(x));
}

cl_object
cl_sqrt(cl_object x)
{
	cl_object z;
	cl_type tx;
 AGAIN:
	tx = type_of(x);
	if (!ECL_NUMBER_TYPE_P(tx)) {
		x = ecl_type_error(@'sqrt',"argument",x,@'number');
		goto AGAIN;
	}
	if (tx == t_complex) {
		z = ecl_make_ratio(MAKE_FIXNUM(1), MAKE_FIXNUM(2));
		z = cl_expt(x, z);
	} else if (ecl_minusp(x)) {
		z = ecl_make_complex(MAKE_FIXNUM(0), cl_sqrt(ecl_negate(x)));
	} else switch (type_of(x)) {
	case t_fixnum:
	case t_bignum:
	case t_ratio:
		z = ecl_make_singlefloat(sqrtf(number_to_float(x))); break;
#ifdef ECL_SHORT_FLOAT
	case t_shortfloat:
		z = make_shortfloat(sqrtf(ecl_short_float(x))); break;;
#endif
	case t_singlefloat:
		z = ecl_make_singlefloat(sqrtf(sf(x))); break;
	case t_doublefloat:
		z = ecl_make_doublefloat(sqrt(df(x))); break;
#ifdef ECL_LONG_FLOAT
	case t_longfloat:
		z = make_longfloat(sqrtl(ecl_long_float(x))); break;
#endif
	default:
		/* Never reaches this */
		(void)0;
	}
	@(return z);
}

cl_object
ecl_atan2(cl_object y, cl_object x)
{
	cl_object z;
	double dy, dx, dz;

	dy = ecl_to_double(y);
	dx = ecl_to_double(x);
	if (dx > 0.0)
		if (dy > 0.0)
			dz = atan(dy / dx);
		else if (dy == 0.0)
			dz = 0.0;
		else
			dz = -atan(-dy / dx);
	else if (dx == 0.0)
		if (dy > 0.0)
			dz = M_PI / 2.0;
		else if (dy == 0.0)
			FEerror("Logarithmic singularity.", 0);
		else
			dz = -M_PI / 2.0;
	else
		if (dy > 0.0)
			dz = M_PI - atan(dy / -dx);
		else if (dy == 0.0)
			dz = M_PI;
		else
			dz = -M_PI + atan(-dy / -dx);
	if (type_of(x) == t_doublefloat || type_of(y) == t_doublefloat)
		return ecl_make_doublefloat(dz);
	else
		return ecl_make_singlefloat(dz);
}

cl_object
ecl_atan1(cl_object y)
{
	if (type_of(y) == t_complex) {
#if 0 /* FIXME! ANSI states it should be this first part */
		z = ecl_times(cl_core.imag_unit, y);
		z = ecl_log1(ecl_one_plus(z)) +
		    ecl_log1(ecl_minus(MAKE_FIXNUM(1), z));
		z = ecl_divide(z, ecl_times(MAKE_FIXNUM(2), cl_core.imag_unit));
#else
		cl_object z1, z = ecl_times(cl_core.imag_unit, y);
		z = ecl_one_plus(z);
		z1 = ecl_times(y, y);
		z1 = ecl_one_plus(z1);
		z1 = cl_sqrt(z1);
		z = ecl_divide(z, z1);
		z = ecl_log1(z);
		z = ecl_times(cl_core.minus_imag_unit, z);
#endif /* ANSI */
		return z;
	} else {
		return ecl_atan2(y, MAKE_FIXNUM(1));
	}
}

cl_object
cl_sin(cl_object x)
{
	cl_object output;
 AGAIN:
	switch (type_of(x)) {
	case t_fixnum:
	case t_bignum:
	case t_ratio:
		output = ecl_make_singlefloat(sinf(number_to_float(x))); break;
#ifdef ECL_SHORT_FLOAT
	case t_shortfloat:
		output = make_shortfloat(sinf(ecl_short_float(x))); break;
#endif
	case t_singlefloat:
		output = ecl_make_singlefloat(sinf(sf(x))); break;
	case t_doublefloat:
		output = ecl_make_doublefloat(sin(df(x))); break;
#ifdef ECL_LONG_FLOAT
	case t_longfloat:
		output = make_longfloat(sinf(ecl_long_float(x))); break;
#endif
	case t_complex: {
		/*
		  z = x + I y
		  z = x + I y
		  sin(z) = sinh(I z) = sinh(-y + I x)
		*/
		double dx = ecl_to_double(x->complex.real);
		double dy = ecl_to_double(x->complex.imag);
		double a = sin(dx) * cosh(dy);
		double b = cos(dx) * sinh(dy);
		if (type_of(x->complex.real) != t_doublefloat)
			output = ecl_make_complex(ecl_make_singlefloat(a),
					      ecl_make_singlefloat(b));
		else
			output = ecl_make_complex(ecl_make_doublefloat(a),
					      ecl_make_doublefloat(b));
		break;
	}
	default:
		x = ecl_type_error(@'sin',"argument",x,@'number');
		goto AGAIN;
	}
	@(return output)
}

cl_object
cl_cos(cl_object x)
{
	cl_object output;
 AGAIN:
	switch (type_of(x)) {
	case t_fixnum:
	case t_bignum:
	case t_ratio:
		output = ecl_make_singlefloat(cosf(number_to_float(x))); break;
#ifdef ECL_SHORT_FLOAT
	case t_shortfloat:
		output = make_shortfloat(cosf(ecl_short_float(x))); break;
#endif
	case t_singlefloat:
		output = ecl_make_singlefloat(cosf(sf(x))); break;
	case t_doublefloat:
		output = ecl_make_doublefloat(cos(df(x))); break;
#ifdef ECL_LONG_FLOAT
	case t_longfloat:
		output = make_longfloat(cosl(ecl_long_float(x))); break;
#endif
	case t_complex: {
		/*
		  z = x + I y
		  cos(z) = cosh(I z) = cosh(-y + I x)
		*/
		double dx = ecl_to_double(x->complex.real);
		double dy = ecl_to_double(x->complex.imag);
		double a =  cos(dx) * cosh(dy);
		double b = -sin(dx) * sinh(dy);
		if (type_of(x->complex.real) != t_doublefloat)
			output = ecl_make_complex(ecl_make_singlefloat(a),
					      ecl_make_singlefloat(b));
		else
			output = ecl_make_complex(ecl_make_doublefloat(a),
					      ecl_make_doublefloat(b));
		break;
	}
	default:
		x = ecl_type_error(@'cos',"argument",x,@'number');
		goto AGAIN;
	}
	@(return output)
}

cl_object
cl_tan(cl_object x)
{
	cl_object output;
 AGAIN:
	switch (type_of(x)) {
	case t_fixnum:
	case t_bignum:
	case t_ratio:
		output = ecl_make_singlefloat(tanf(number_to_float(x))); break;
#ifdef ECL_SHORT_FLOAT
	case t_shortfloat:
		output = make_shortfloat(tanf(ecl_short_float(x))); break;
#endif
	case t_singlefloat:
		output = ecl_make_singlefloat(tanf(sf(x))); break;
	case t_doublefloat:
		output = ecl_make_doublefloat(tan(df(x))); break;
#ifdef ECL_LONG_FLOAT
	case t_longfloat:
		output = make_longfloat(tanl(ecl_long_float(x))); break;
#endif
	case t_complex: {
		cl_object a = cl_sin(x);
		cl_object b = cl_cos(x);
		output = ecl_divide(a, b);
		break;
	}
	default:
		x = ecl_type_error(@'tan',"argument",x,@'number');
		goto AGAIN;
	}
	@(return output)
}

cl_object
cl_sinh(cl_object x)
{
	cl_object output;
 AGAIN:
	switch (type_of(x)) {
	case t_fixnum:
	case t_bignum:
	case t_ratio:
		output = ecl_make_singlefloat(sinhf(number_to_float(x))); break;
#ifdef ECL_SHORT_FLOAT
	case t_shortfloat:
		output = make_shortfloat(sinhf(ecl_short_float(x))); break;
#endif
	case t_singlefloat:
		output = ecl_make_singlefloat(sinhf(sf(x))); break;
	case t_doublefloat:
		output = ecl_make_doublefloat(sinh(df(x))); break;
#ifdef ECL_LONG_FLOAT
	case t_longfloat:
		output = make_longfloat(sinhf(ecl_long_float(x))); break;
#endif
	case t_complex: {
		/*
		  z = x + I y
		  sinh(z) = (exp(z)-exp(-z))/2
		          = (exp(x)*(cos(y)+Isin(y))-exp(-x)*(cos(y)-Isin(y)))/2
			  = sinh(x)*cos(y) + Icosh(x)*sin(y);
		*/
		double dx = ecl_to_double(x->complex.real);
		double dy = ecl_to_double(x->complex.imag);
		double a = sinh(dx) * cos(dy);
		double b = cosh(dx) * sin(dy);
		if (type_of(x->complex.real) != t_doublefloat)
			output = ecl_make_complex(ecl_make_singlefloat(a),
					      ecl_make_singlefloat(b));
		else
			output = ecl_make_complex(ecl_make_doublefloat(a),
					      ecl_make_doublefloat(b));
		break;
	}
	default:
		x = ecl_type_error(@'sinh',"argument",x,@'number');
		goto AGAIN;
	}
	@(return output)
}

cl_object
cl_cosh(cl_object x)
{
	cl_object output;
 AGAIN:
	switch (type_of(x)) {
	case t_fixnum:
	case t_bignum:
	case t_ratio:
		output = ecl_make_singlefloat(coshf(number_to_float(x))); break;
#ifdef ECL_SHORT_FLOAT
	case t_shortfloat:
		output = make_shortfloat(coshf(ecl_short_float(x))); break;
#endif
	case t_singlefloat:
		output = ecl_make_singlefloat(coshf(sf(x))); break;
	case t_doublefloat:
		output = ecl_make_doublefloat(cosh(df(x))); break;
#ifdef ECL_LONG_FLOAT
	case t_longfloat:
		output = make_longfloat(coshl(ecl_long_float(x))); break;
#endif
	case t_complex: {
		/*
		  z = x + I y
		  cosh(z) = (exp(z)+exp(-z))/2
		          = (exp(x)*(cos(y)+Isin(y))+exp(-x)*(cos(y)-Isin(y)))/2
			  = cosh(x)*cos(y) + Isinh(x)*sin(y);
		*/
		double dx = ecl_to_double(x->complex.real);
		double dy = ecl_to_double(x->complex.imag);
		double a = cosh(dx) * cos(dy);
		double b = sinh(dx) * sin(dy);
		if (type_of(x->complex.real) != t_doublefloat)
			output = ecl_make_complex(ecl_make_singlefloat(a),
					      ecl_make_singlefloat(b));
		else
			output = ecl_make_complex(ecl_make_doublefloat(a),
					      ecl_make_doublefloat(b));
		break;
	}
	default:
		x = ecl_type_error(@'cosh',"argument",x,@'number');
		goto AGAIN;
	}
	@(return output)
}

cl_object
cl_tanh(cl_object x)
{
	cl_object output;
 AGAIN:
	switch (type_of(x)) {
	case t_fixnum:
	case t_bignum:
	case t_ratio:
		output = ecl_make_singlefloat(tanhf(number_to_float(x))); break;
#ifdef ECL_SHORT_FLOAT
	case t_shortfloat:
		output = make_shortfloat(tanhf(ecl_short_float(x))); break;
#endif
	case t_singlefloat:
		output = ecl_make_singlefloat(tanhf(sf(x))); break;
	case t_doublefloat:
		output = ecl_make_doublefloat(tanh(df(x))); break;
#ifdef ECL_LONG_FLOAT
	case t_longfloat:
		output = make_longfloat(coshl(ecl_long_float(x))); break;
#endif
	case t_complex: {
		cl_object a = cl_sinh(x);
		cl_object b = cl_cosh(x);
		output = ecl_divide(a, b);
		break;
	}
	default:
		x = ecl_type_error(@'tanh',"argument",x,@'number');
		goto AGAIN;
	}
	@(return output)
}

@(defun log (x &optional (y OBJNULL))
@	/* INV: type check in ecl_log1() and ecl_log2() */
	if (y == OBJNULL)
		@(return ecl_log1(x))
	@(return ecl_log2(y, x))
@)

@(defun atan (x &optional (y OBJNULL))
@	/* INV: type check in ecl_atan() & ecl_atan2() */
	/* FIXME ecl_atan() and ecl_atan2() produce generic errors
	   without recovery and function information. */
	if (y == OBJNULL)
		@(return ecl_atan1(x))
	@(return ecl_atan2(x, y))
@)
