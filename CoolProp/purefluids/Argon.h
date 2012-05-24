#include "FluidClass.h"
#ifndef ARGON_H
#define ARGON_H

	class ArgonClass : public Fluid{

	private:
		double X_tilde(double T,double tau,double delta);
	public:
		ArgonClass();
		~ArgonClass(){};
		virtual double conductivity_Trho(double, double);
		virtual double viscosity_Trho(double, double);
		double psat(double);
		double rhosatL(double);
		double rhosatV(double);
		
	};
#endif