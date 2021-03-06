#cython: embedsignature = True, c_string_type=str, c_string_encoding=ascii
from __future__ import division 
#
#
# This file provides wrapper functions of all the CoolProp functions
#
#
# Each of the functions from the CoolProp header are renamed in cython code to
# an underscored name so that the same name can be used in the exposed functions below
    
#Check for the existence of quantities
cdef bint _quantities_supported
try:
    import quantities as pq
    _quantities_supported = True
except ImportError:
    _quantities_supported = False
    
#Check for the existence of numpy
cdef bint _numpy_supported
try:
    import numpy as np
    _numpy_supported = True
except ImportError:
    _numpy_supported = False

import cython
import math

# Default string in Python 3.x is a unicode string (type str)
# Default string in Python 2.x is a byte string(type bytes) 
#
# Create a fused type that allows for either unicode string or bytestring
# We encode unicode strings using the ASCII encoding since we know they are all
# ASCII strings 
ctypedef fused bytes_or_str:
    cython.bytes
    cython.str

include "CyState.pyx"

from param_constants import *
from param_constants_header cimport *

from phase_constants import *
from phase_constants_header cimport *

include "HumidAirProp.pyx"

cdef double _convert_to_desired_units(double value, bytes_or_str parameter_type, bytes_or_str desired_units) except *:
    """
    A convenience function to convert a double value back to the units that
    are desired by the user
    """
    # Convert parameter string to index
    cdef long index = _get_param_index(parameter_type)
    # Get the units string by the index
    cdef bytes default_units = _get_index_units(index)
    # Create the Quantity instance
    old = pq.Quantity(value, default_units)
    # Convert the units
    old.units = _desired_units
    #Return the scaled units
    return old.magnitude

cdef _convert_to_default_units(bytes_or_str parameter_type, object parameter):
    """
    A convenience function to convert a quantities instance to the default 
    units required for CoolProp
    """
    #Convert parameter string to index
    cdef long index = _get_param_index(parameter_type)
    #Get the units string by the index
    cdef bytes default_units = _get_index_units(index)
    #Rescale the units of the parameter to the default units
    parameter.units = default_units
    #Return the scaled units
    return parameter
    
def set_reference_state(bytes_or_str FluidName, *args):
    """
    Accepts one of two signatures:
    
    Type #1:
    
    set_reference_state(FluidName,reference_state)
    
    FluidName The name of the fluid
    param reference_state The reference state to use, one of 
    
    ==========   ===========================================
    ``IIR``      (h=200 kJ/kg, s=1 kJ/kg/K at 0C sat. liq.)
    ``ASHRAE``   (h=0,s=0 @ -40C sat liq)
    ``NBP``      (h=0,s=0 @ 1.0 bar sat liq.)
    ==========   ============================================
    
    Type #2:
    
    set_reference_state(FluidName,T0,rho0,h0,s0)
    
    ``FluidName`` The name of the fluid
    
    ``T0`` The temperature at the reference point [K]
    
    ``rho0`` The density at the reference point [kg/m^3]
    
    ``h0`` The enthalpy at the reference point [J/kg]
    
    ``s0`` The entropy at the reference point [J/kg]
    """
    
    cdef bytes _param
    cdef int retval
    
    if len(args) == 1:
        _param = args[0].encode('ascii')
        retval = _set_reference_stateS(FluidName, _param)
    elif len(args) == 4:
        retval = _set_reference_stateD(FluidName, args[0], args[1], args[2], args[3])
    else:
        raise ValueError('Invalid number of inputs')
    
    if retval < 0:
        raise ValueError('Unable to set reference state')
        
cpdef add_REFPROP_fluid(bytes_or_str FluidName):
    """
    Add a REFPROP fluid to CoolProp internal structure
    
    example::
    
        add_REFPROP_fluid("REFPROP-PROPANE")
         
    """
    _add_REFPROP_fluid(FluidName)
    
cpdef long get_Fluid_index(bytes_or_str Fluid):
    """
    Gets the integer index of the given CoolProp fluid (primarily for use in ``IProps`` function)
    """
    return _get_Fluid_index(Fluid)
    
cpdef double IProps(long iOutput, long iInput1, double Input1, long iInput2, double Input2, long iFluid) except *:
    """
    This is a more computationally efficient version of the Props() function as it uses integer keys for the input and output codes as well as the fluid index for the fluid.  It can only be used with CoolProp fluids.  An example of how it should be used::
    
        #  These should be run once in the header of your file
        from CoolProp.CoolProp import IProps, get_Fluid_index
        from CoolProp import param_constants
        iPropane = get_Fluid_index('Propane')
        
        #  This should be run using the cached values - much faster !
        IProps(param_constants.iP,param_constants.iT,0.8*Tc,param_constants.iQ,1,iPropane)
        
    The reason that this function is significantly faster than Props is that it skips all the string comparisons which slows down the Props function quite a lot.  At the C++ level, IProps doesn't use any strings and operates on integers and floating point values
    """
    cdef double val = _IProps(iOutput, iInput1, Input1, iInput2, Input2, iFluid)
    
    if math.isinf(val) or math.isnan(val):
        err_string = _get_global_param_string('errstring')
        if not len(err_string) == 0:
            raise ValueError("{err:s} :: inputs were :{iin1:d},{in1:g},{iin2:d},{in2:g},{iFluid:d}".format(err= err_string,iin1=iInput1,in1=Input1,iin2=iInput2,in2=Input2,iFluid = iFluid))
        else:
            raise ValueError("IProps failed ungracefully with inputs:\"{in1:g}\",\"{in2:g}\"; please file a ticket at https://sourceforge.net/p/coolprop/tickets/".format(in1=Input1,in2=Input2))
    else:
        return val

cpdef get_global_param_string(bytes_or_str param):
    return _get_global_param_string(param)
    
cpdef get_fluid_param_string(bytes_or_str fluid, bytes_or_str param):
    return _get_fluid_param_string(fluid, param)
    
def isConstant(what):
    """Get the boolean telling you if 
    the given key matches with a fluid constant. 
    """
    altFactors = {
      "Tcrit"     : 1.      ,#Critical temperature [K]
      "pcrit"     : 1./1000.,#Critical pressure [kPa]
      "Psat"      : 1./1000.,#Saturation pressure [kPa]
      "rhocrit"   : 1.      ,#Critical density [kg/m3]
      "molemass"  : 1./1000.,#Molecular mass [kg/kmol]
      "Ttriple"   : 1.      ,#Triple-point temperature [K]
      "Tmin"      : 1.      ,#Minimum temperature [K]
      "Tmax"      : 1.      ,#Maximum temperature [K]
      "Tfreeze"   : 1.      ,#Freezing temperature [K]
      "ptriple"   : 1./1000.,#Triple-point pressure [kPa]
      "accentric" : 1.      ,#Accentric factor [-]
      "GWP100"    : 1.      ,#Global Warming Potential 100 yr
      "ODP"       : 1.       #Ozone Depletion Potential
    }
    if what in altFactors:
        return True
    else:
        return False
        #msg = 'Your input '+str(what)+' does not match any of the stored keys '+str(list(factors.keys()))+'.'
        #print msg
        #raise ValueError(msg)

def PropsU(in1, in2, in3 = None, in4 = None, in5 = None, in6 = None, in7 = None):
    """Make the Props function handle different kinds of unit sets. Use 
    kSI or SI to identify your desired unit system. Both input and output 
    values have to be from the same unit set.  
    """
    if in7 is None or in7 == 'kSI': # Nothing has to be done 
        return Props(in1, in2, in3, in4, in5, in6)
    elif in7 == 'SI':
        if isConstant(in2):
            return toSI(in2,Props(in1, in2, in3, in4, in5, in6), 'kSI')
        else:
            in3kSI = fromSI(in2, in3, 'kSI')
            in5kSI = fromSI(in4, in5, 'kSI')
            return toSI(in1,Props(in1, in2, in3kSI, in4, in5kSI, in6), 'kSI')
    else:
        msg = 'Your requested unit set '+str(in7)+' is not supported, valid unit definitions are kSI and SI only.'
        #print msg
        raise ValueError(msg)

cpdef fromSI(str in1, in2=None, str in3 = 'kSI'):
    """
    Call fromSI(Property, Value, Units) to convert from SI units to a given set of units. 
    At the moment, only kSI is supported. This convenience function is used inside both the
    PropsU and DerivTermsU functions. 
    """
    if isinstance(in2, (int, long, float, complex)): #is not iterable
        return _fromSI(in1, in2, in3)
    else: # iterable or error
        result = [_fromSI(in1, inV, in3) for inV in in2]
        if _numpy_supported:
            return np.array(result)
        else:
            return result

cpdef toSI(str in1, in2=None, str in3='kSI'):
    """
    Call toSI(Property, Value, Units) to convert from a given set of units to SI units. 
    At the moment, only kSI is supported. This convenience function is used inside both the
    PropsU and DerivTermsU functions. 
    """
    if isinstance(in2, (int, long, float, complex)): #is not iterable
        return _toSI(in1, in2, in3)
    else: # iterable or error
        result = [_toSI(in1, inV, in3) for inV in in2]
        if _numpy_supported:
            return np.array(result)
        else:
            return result
    
cpdef Props(str in1, str in2, in3 = None, in4 = None, in5 = None, in6 = None, in7 = None):
    """
    Call Type #1::

        Props(Fluid,PropName) --> float

    Where ``Fluid`` is a string with a valid CoolProp fluid name, and ``PropName`` is one of the following strings:
    
    =============  ============================
    ``Tcrit``      Critical temperature [K]
    ``Treduce``    Reducing temperature [K]
    ``pcrit``      Critical pressure [kPa]
    ``rhocrit``    Critical density [kg/m3]
    ``rhoreduce``  Reducing density [kg/m3]
    ``molemass``   Molecular mass [kg/kmol]
    ``Ttriple``    Triple-point temperature [K]
    ``Tmin``       Minimum temperature [K]
    ``ptriple``    Triple-point pressure [kPa]
    ``accentric``  Accentric factor [-]
    ``GWP100``     Global Warming Potential 100 yr
    ``ODP``        Ozone Depletion Potential
    =============  ============================
   
    This type of call is used to get fluid-specific parameters that are not 
    dependent on the state 
     
    Call Type #2:
    
    Alternatively, Props can be called in the form::
    
        Props(OutputName,InputName1,InputProp1,InputName2,InputProp2,Fluid) --> float
    
    where ``Fluid`` is a string with a valid CoolProp fluid name.  The value 
    ``OutputName`` is either a single-character or a string alias.  This list 
    shows the possible values
    
    ==========================  ======================================================
    ``OutputName``              Description
    ==========================  ======================================================
    ``Q``                       Quality [-]
    ``T``                       Temperature [K]
    ``P``                       Pressure [kPa]
    ``D``                       Density [kg/m3]
    ``C0``                      Ideal-gas specific heat at constant pressure [kJ/kg/K]
    ``C``                       Specific heat at constant pressure [kJ/kg/K]
    ``O``                       Specific heat at constant volume [kJ/kg/K]
    ``U``                       Internal energy [kJ/kg]
    ``H``                       Enthalpy [kJ/kg]
    ``S``                       Entropy [kJ/kg/K]
    ``A``                       Speed of sound [m/s]
    ``G``                       Gibbs function [kJ/kg]
    ``V``                       Dynamic viscosity [Pa-s]
    ``L``                       Thermal conductivity [kW/m/K]
    ``I`` or `SurfaceTension`   Surface Tension [N/m]
    ``w`` or `accentric`        Accentric Factor [-]
    ==========================  ======================================================
    
    The following sets of input values are valid (order doesn't matter):
    
    =========================  ======================================
    ``InputName1``             ``InputName2``
    =========================  ======================================
    ``T``                      ``P``
    ``T``                      ``D``
    ``P``                      ``D``
    ``T``                      ``Q``
    ``P``                      ``Q``
    ``H``                      ``P``
    ``S``                      ``P``
    ``S``                      ``H``
    =========================  ======================================
    
    **Python Only** : InputProp1 and InputProp2 can be lists or numpy arrays.  If both are iterables, they must be the same size. 
    
    
    If `InputName1` is `T` and `OutputName` is ``I`` or ``SurfaceTension``, the second input is neglected
    since surface tension is only a function of temperature
    
    Call Type #3:
    New in 2.2
    If you provide InputName1 or InputName2 as a derived class of Quantity, the value will be internally
    converted to the required units as long as it is dimensionally correct.  Otherwise a ValueError will 
    be raised by the conversion
    """
    cdef bytes errs,_in1,_in2,_in4,_in6,_in7
    cdef double _in3, _in5
    cdef char in2_char, in4_char
        
    if (in4 is None and in6 is None and in7 is None):
        val = _Props1(in1.encode('ascii'), in2.encode('ascii'))
        if math.isinf(val) or math.isnan(val):
            err_string = _get_global_param_string('errstring')
            if not len(err_string) == 0:
                raise ValueError("{err:s} :: inputs were :\"{in1:s}\",\"{in2:s}\"".format(err= err_string,in1=in1,in2=in2))
            else:
                raise ValueError("Props failed ungracefully with inputs:\"{in1:s}\",\"{in2:s}\"; please file a ticket at https://github.com/ibell/coolprop/issues".format(in1=in1,in2=in2))
        else:
            return val
    else:
        if _quantities_supported:
            if isinstance(in3,pq.Quantity):
                in3 = _convert_to_default_units(in2,in3).magnitude
            if isinstance(in5,pq.Quantity):
                in5 = _convert_to_default_units(<bytes?>in4,in5).magnitude

        in2_char = (<bytes>(in2.encode('ascii')))[0]
        in4_char = (<bytes>(in4.encode('ascii')))[0]
        
        if isinstance(in3, (int, long, float, complex)) and isinstance(in5, (int, long, float, complex)):
            val = _Props(in1.encode('ascii'), in2_char, in3, in4_char, in5, in6.encode('ascii'))
        
            if math.isinf(val) or math.isnan(val):
                err_string = _get_global_param_string('errstring')
                if not len(err_string) == 0:
                    raise ValueError("{err:s} :: inputs were:\"{in1:s}\",\'{in2:s}\',{in3:0.16e},\'{in4:s}\',{in5:0.16e},\"{in6:s}\"".format(err=err_string,in1=in1,in2=in2,in3=in3,in4=in4,in5=in5,in6=in6))
                else:
                    raise ValueError("Props failed ungracefully with inputs:\"{in1:s}\",\'{in2:s}\',{in3:0.16e},\'{in4:s}\',{in5:0.16e},\"{in6:s}\"; please file a ticket at https://github.com/ibell/coolprop/issues".format(in1=in1,in2=in2,in3=in3,in4=in4,in5=in5,in6=in6))
            
            if not _quantities_supported and in7 is not None:
                raise ValueError("Cannot use output units because quantities package is not installed")
            elif _quantities_supported and in7 is not None: #Then in7 contains a string representation of the units
                #Convert the units to the units given by in7
                return _convert_to_desired_units(val,in1,in7)
            else:
                return val #Error raised by Props2 on failure
            
        elif isinstance(in3, (int, long, float, complex)): #in5 can be an iterable
            vals = []
            for _in5 in in5:
                val = _Props(in1.encode('ascii'), in2_char, in3, in4_char, _in5, in6.encode('ascii'))
            
                if math.isinf(val) or math.isnan(val):
                    err_string = _get_global_param_string('errstring')
                    if not len(err_string) == 0:
                        raise ValueError("{err:s} :: inputs were:\"{in1:s}\",\'{in2:s}\',{in3:0.16e},\'{in4:s}\',{in5:0.16e},\"{in6:s}\"".format(err=err_string,in1=in1,in2=in2,in3=in3,in4=in4,in5=_in5,in6=in6))
                    else:
                        raise ValueError("Props failed ungracefully with inputs:\"{in1:s}\",\'{in2:s}\',{in3:0.16e},\'{in4:s}\',{in5:0.16e},\"{in6:s}\"; please file a ticket at https://github.com/ibell/coolprop/issues".format(in1=in1,in2=in2,in3=in3,in4=in4,in5=_in5,in6=in6))
                
                if not _quantities_supported and in7 is not None:
                    raise ValueError("Cannot use output units because quantities package is not installed")
                elif _quantities_supported and in7 is not None: #Then in7 contains a string representation of the units
                    #Convert the units to the units given by in7
                    val = _convert_to_desired_units(val,in1,in7)
                
                vals.append(val)
                
            if _numpy_supported and isinstance(in5, np.ndarray):
                return np.array(vals).reshape(in5.shape)
            else:
                return type(in5)(vals)
        
        elif isinstance(in5, (int, long, float, complex)): #in3 can be an iterable
            vals = []
            for _in3 in in3:
                val = _Props(in1.encode('ascii'), in2_char, _in3, in4_char, in5, in6.encode('ascii'))
            
                if math.isinf(val) or math.isnan(val):
                    err_string = _get_global_param_string('errstring')
                    if not len(err_string) == 0:
                        raise ValueError("{err:s} :: inputs were:\"{in1:s}\",\'{in2:s}\',{in3:0.16e},\'{in4:s}\',{in5:0.16e},\"{in6:s}\"".format(err=err_string,in1=in1,in2=in2,in3=_in3,in4=in4,in5=in5,in6=in6))
                    else:
                        raise ValueError("Props failed ungracefully with inputs:\"{in1:s}\",\'{in2:s}\',{in3:0.16e},\'{in4:s}\',{in5:0.16e},\"{in6:s}\"; please file a ticket at https://github.com/ibell/coolprop/issues".format(in1=in1,in2=in2,in3=_in3,in4=in4,in5=in5,in6=in6))
                
                if not _quantities_supported and in7 is not None:
                    raise ValueError("Cannot use output units because quantities package is not installed")
                elif _quantities_supported and in7 is not None: #Then in7 contains a string representation of the units
                    #Convert the units to the units given by in7
                    val = _convert_to_desired_units(val,in1,in7)
                
                vals.append(val)
                
            if _numpy_supported and isinstance(in3, np.ndarray):
                return np.array(vals).reshape(in3.shape)
            else:
                return type(in3)(vals)
        else: #Either both are iterables or its a failure
            if not len(in3) == len(in5):
                raise TypeError('Both iterables must be the same length') 
            try:
                vals = []
                for _in3,_in5 in zip(in3,in5):
                    val = _Props(in1.encode('ascii'), in2_char, _in3, in4_char, _in5, in6.encode('ascii'))
                
                    if math.isinf(val) or math.isnan(val):
                        err_string = _get_global_param_string('errstring') 
                        if not len(err_string) == 0:
                            raise ValueError("{err:s} :: inputs were:\"{in1:s}\",\'{in2:s}\',{in3:0.16e},\'{in4:s}\',{in5:0.16e},\"{in6:s}\"".format(err=err_string,in1=in1,in2=in2,in3=_in3,in4=in4,in5=_in5,in6=in6))
                        else:
                            raise ValueError("Props failed ungracefully with inputs:\"{in1:s}\",\'{in2:s}\',{in3:0.16e},\'{in4:s}\',{in5:0.16e},\"{in6:s}\"; please file a ticket at https://github.com/ibell/coolprop/issues".format(in1=in1,in2=in2,in3=_in3,in4=in4,in5=_in5,in6=in6))
                    
                    if not _quantities_supported and in7 is not None:
                        raise ValueError("Cannot use output units because quantities package is not installed")
                    elif _quantities_supported and in7 is not None: #Then in7 contains a string representation of the units
                        #Convert the units to the units given by in7
                        val = _convert_to_desired_units(val,in1,in7)
                    
                    vals.append(val)
                    
                if _numpy_supported and isinstance(in3, np.ndarray):
                    return np.array(vals).reshape(in3.shape)
                else:
                    return type(in3)(vals)
            except TypeError:   
                raise TypeError('Numerical inputs to Props must be ints, floats, lists, or 1D numpy arrays.')
                
cpdef PropsSI(str in1, str in2, in3 = None, in4 = None, in5 = None, in6 = None, in7 = None):
    """
    Just like Props(), but this function ALWAYS takes in and returns SI units (K, kg, J/kg, Pa, N/m, etc.)
    
    Call Type #1::

        Props(Fluid,PropName) --> float

    Where ``Fluid`` is a string with a valid CoolProp fluid name, and ``PropName`` is one of the following strings:
    
    =============  ============================
    ``Tcrit``      Critical temperature [K]
    ``Treduce``    Reducing temperature [K]
    ``pcrit``      Critical pressure [Pa]
    ``rhocrit``    Critical density [kg/m3]
    ``rhoreduce``  Reducing density [kg/m3]
    ``molemass``   Molecular mass [kg/kmol]
    ``Ttriple``    Triple-point temperature [K]
    ``Tmin``       Minimum temperature [K]
    ``ptriple``    Triple-point pressure [Pa]
    ``accentric``  Accentric factor [-]
    ``GWP100``     Global Warming Potential 100 yr
    ``ODP``        Ozone Depletion Potential
    =============  ============================
   
    This type of call is used to get fluid-specific parameters that are not 
    dependent on the state 
     
    Call Type #2:
    
    Alternatively, Props can be called in the form::
    
        Props(OutputName,InputName1,InputProp1,InputName2,InputProp2,Fluid) --> float
    
    where ``Fluid`` is a string with a valid CoolProp fluid name.  The value 
    ``OutputName`` is either a single-character or a string alias.  This list 
    shows the possible values
    
    ==========================  ======================================================
    ``OutputName``              Description
    ==========================  ======================================================
    ``Q``                       Quality [-]
    ``T``                       Temperature [K]
    ``P``                       Pressure [Pa]
    ``D``                       Density [kg/m3]
    ``C0``                      Ideal-gas specific heat at constant pressure [J/kg]
    ``C``                       Specific heat at constant pressure [J/kg]
    ``O``                       Specific heat at constant volume [J/kg]
    ``U``                       Internal energy [J/kg]
    ``H``                       Enthalpy [J/kg]
    ``S``                       Entropy [J/kg/K]
    ``A``                       Speed of sound [m/s]
    ``G``                       Gibbs function [J/kg]
    ``V``                       Dynamic viscosity [Pa-s]
    ``L``                       Thermal conductivity [W/m/K]
    ``I`` or `SurfaceTension`   Surface Tension [N/m]
    ``w`` or `accentric`        Accentric Factor [-]
    ==========================  ======================================================
    
    The following sets of input values are valid (order doesn't matter):
    
    =========================  ======================================
    ``InputName1``             ``InputName2``
    =========================  ======================================
    ``T``                      ``P``
    ``T``                      ``D``
    ``P``                      ``D``
    ``T``                      ``Q``
    ``P``                      ``Q``
    ``H``                      ``P``
    ``S``                      ``P``
    ``S``                      ``H``
    =========================  ======================================
    
    **Python Only** : InputProp1 and InputProp2 can be lists or numpy arrays.  If both are iterables, they must be the same size. 
    
    
    If `InputName1` is `T` and `OutputName` is ``I`` or ``SurfaceTension``, the second input is neglected
    since surface tension is only a function of temperature
    
    """
    cdef bytes errs,_in1,_in2,_in4,_in6,_in7
    cdef double _in3, _in5
    cdef char in2_char, in4_char
        
    if (in4 is None and in6 is None and in7 is None):
        val = _Props1(in1.encode('ascii'), in2.encode('ascii'))
        if math.isinf(val) or math.isnan(val):
            err_string = _get_global_param_string('errstring')
            if not len(err_string) == 0:
                raise ValueError("{err:s} :: inputs were :\"{in1:s}\",\"{in2:s}\"".format(err= err_string,in1=in1,in2=in2))
            else:
                raise ValueError("Props failed ungracefully with inputs:\"{in1:s}\",\"{in2:s}\"; please file a ticket at https://github.com/ibell/coolprop/issues".format(in1=in1,in2=in2))
        else:
            return val
    else:
        
        if isinstance(in3, (int, long, float, complex)) and isinstance(in5, (int, long, float, complex)):
            val = _PropsSI(in1, in2, in3, in4, in5, in6)
        
            if math.isinf(val) or math.isnan(val):
                err_string = _get_global_param_string('errstring')
                if not len(err_string) == 0:
                    raise ValueError("{err:s} :: inputs were:\"{in1:s}\",\'{in2:s}\',{in3:0.16e},\'{in4:s}\',{in5:0.16e},\"{in6:s}\"".format(err=err_string,in1=in1,in2=in2,in3=in3,in4=in4,in5=in5,in6=in6))
                else:
                    raise ValueError("PropsSI failed ungracefully with inputs:\"{in1:s}\",\'{in2:s}\',{in3:0.16e},\'{in4:s}\',{in5:0.16e},\"{in6:s}\"; please file a ticket at https://github.com/ibell/coolprop/issues".format(in1=in1,in2=in2,in3=in3,in4=in4,in5=in5,in6=in6))
            
            return val 
            
        elif isinstance(in3, (int, long, float, complex)): #in5 can be an iterable
            vals = []
            for _in5 in in5:
                val = _PropsSI(in1, in2, in3, in4, _in5, in6)
            
                if math.isinf(val) or math.isnan(val):
                    err_string = _get_global_param_string('errstring')
                    if not len(err_string) == 0:
                        raise ValueError("{err:s} :: inputs were:\"{in1:s}\",\'{in2:s}\',{in3:0.16e},\'{in4:s}\',{in5:0.16e},\"{in6:s}\"".format(err=err_string,in1=in1,in2=in2,in3=in3,in4=in4,in5=_in5,in6=in6))
                    else:
                        raise ValueError("Props failed ungracefully with inputs:\"{in1:s}\",\'{in2:s}\',{in3:0.16e},\'{in4:s}\',{in5:0.16e},\"{in6:s}\"; please file a ticket at https://github.com/ibell/coolprop/issues".format(in1=in1,in2=in2,in3=in3,in4=in4,in5=_in5,in6=in6))
                
                vals.append(val)
                
            if _numpy_supported and isinstance(in5, np.ndarray):
                return np.array(vals).reshape(in5.shape)
            else:
                return type(in5)(vals)
        
        elif isinstance(in5, (int, long, float, complex)): #in3 can be an iterable
            vals = []
            for _in3 in in3:
                val = _PropsSI(in1, in2, _in3, in4, in5, in6)
            
                if math.isinf(val) or math.isnan(val):
                    err_string = _get_global_param_string('errstring')
                    if not len(err_string) == 0:
                        raise ValueError("{err:s} :: inputs were:\"{in1:s}\",\'{in2:s}\',{in3:0.16e},\'{in4:s}\',{in5:0.16e},\"{in6:s}\"".format(err=err_string,in1=in1,in2=in2,in3=_in3,in4=in4,in5=in5,in6=in6))
                    else:
                        raise ValueError("PropsSI failed ungracefully with inputs:\"{in1:s}\",\'{in2:s}\',{in3:0.16e},\'{in4:s}\',{in5:0.16e},\"{in6:s}\"; please file a ticket at https://github.com/ibell/coolprop/issues".format(in1=in1,in2=in2,in3=_in3,in4=in4,in5=in5,in6=in6))
                
                vals.append(val)
                
            if _numpy_supported and isinstance(in3, np.ndarray):
                return np.array(vals).reshape(in3.shape)
            else:
                return type(in3)(vals)
                
        else: #Either both are iterables or its a failure
            if not len(in3) == len(in5):
                raise TypeError('Both iterables must be the same length') 
            try:
                vals = []
                for _in3,_in5 in zip(in3,in5):
                    val = _PropsSI(in1, in2, _in3, in4, _in5, in6)
                
                    if math.isinf(val) or math.isnan(val):
                        err_string = _get_global_param_string('errstring')
                        if not len(err_string) == 0:
                            raise ValueError("{err:s} :: inputs were:\"{in1:s}\",\'{in2:s}\',{in3:0.16e},\'{in4:s}\',{in5:0.16e},\"{in6:s}\"".format(err=err_string,in1=in1,in2=in2,in3=_in3,in4=in4,in5=_in5,in6=in6))
                        else:
                            raise ValueError("Props failed ungracefully with inputs:\"{in1:s}\",\'{in2:s}\',{in3:0.16e},\'{in4:s}\',{in5:0.16e},\"{in6:s}\"; please file a ticket at https://github.com/ibell/coolprop/issues".format(in1=in1,in2=in2,in3=_in3,in4=in4,in5=_in5,in6=in6))
                    
                    vals.append(val)
                    
                if _numpy_supported and isinstance(in3, np.ndarray):
                    return np.array(vals).reshape(in3.shape)
                else:
                    return type(in3)(vals)
            except TypeError:   
                raise TypeError('Numerical inputs to Props must be ints, floats, lists, or 1D numpy arrays.')

def DerivTermsU(in1, T, rho, fluid, units = None):
    """Make the DerivTerms function handle different kinds of unit sets. Use 
    kSI or SI to identify your desired unit system. Both input and output 
    values have to be from the same unit set.
    """
    if units is None or units == 'kSI':
        return DerivTerms(in1, T, rho, fluid)
    elif units == 'SI':
        return toSI(in1,DerivTerms(in1, T, rho, fluid), 'kSI')
    else:
        msg = 'Your requested unit set '+str(units)+' is not supported, valid unit definitions are kSI and SI only.'
        #print msg
        raise ValueError(msg)
   
cpdef double DerivTerms(str Output, double T, double rho, str Fluid) except +:
    """

    .. |cubed| replace:: \ :sup:`3`\ 
    .. |squared| replace:: \ :sup:`2`\ 
    .. |IC| replace:: ``IsothermalCompressibility``
    
    Call signature::
    
        DerivTerms(OutputName, T, rho, Fluid) --> float
    
    where ``Fluid`` is a string with a valid CoolProp fluid name, and ``T`` and ``rho`` are the temperature in K and density in kg/m |cubed| .  The value 
    ``OutputName`` is one of the strings in the table below:
    
    ========================  =====================================================================================================================================
    OutputName                Description
    ========================  =====================================================================================================================================
    ``dpdT``                  Derivative of pressure with respect to temperature at constant density [kPa/K]
    ``dpdrho``                Derivative of pressure with respect to density at constant temperature [kPa/(kg/m\ |cubed|\ )]
    ``Z``                     Compressibility factor [-]
    ``dZ_dDelta``             Derivative of Z with respect to reduced density [-]
    ``dZ_dTau``               Derivative of Z with respect to inverse reduced temperature [-]
    ``VB``                    Second virial coefficient [m\ |cubed|\ /kg]
    ``dBdT``                  Derivative of second virial coefficient with respect to temperature [m\ |cubed|\ /kg/K]
    ``VC``                    Third virial coefficient [m\ :sup:`6`\ /kg\ |squared|\ ]
    ``dCdT``                  Derivative of third virial coefficient with respect to temperature [m\ :sup:`6`\ /kg\ |squared|\ /K]
    ``phir``                  Residual non-dimensionalized Helmholtz energy [-]
    ``dphir_dTau``            Partial of residual non-dimensionalized Helmholtz energy with respect to inverse reduced temperature [-]
    ``d2phir_dTau2``          Second partial of residual non-dimensionalized Helmholtz energy with respect to inverse reduced temperature [-]
    ``dphir_dDelta``          Partial of residual non-dimensionalized Helmholtz energy with respect to reduced density [-]
    ``d2phir_dDelta2``        Second partial of residual non-dimensionalized Helmholtz energy with respect to reduced density [-]
    ``d2phir_dDelta_dTau``    First cross-partial of residual non-dimensionalized Helmholtz energy [-]
    ``d3phir_dDelta2_dTau``   Second cross-partial of residual non-dimensionalized Helmholtz energy [-]
    ``phi0``                  Ideal-gas non-dimensionalized Helmholtz energy [-]
    ``dphi0_dTau``            Partial of ideal-gas non-dimensionalized Helmholtz energy with respect to inverse reduced temperature [-]
    ``d2phi0_dTau2``          Second partial of ideal-gas non-dimensionalized Helmholtz energy with respect to inverse reduced temperature [-]
    ``dphi0_dDelta``          Partial of ideal-gas non-dimensionalized Helmholtz energy with respect to reduced density [-]
    ``d2phi0_dDelta2``        Second partial of ideal-gas non-dimensionalized Helmholtz energy with respect to reduced density [-]
    |IC|                      Isothermal compressibility [1/kPa]
    ========================  =====================================================================================================================================
    """
    cdef bytes _Fluid = Fluid.encode('ascii')
    cdef bytes _Output = Output.encode('ascii')
    return _DerivTerms(_Output,T,rho,_Fluid)

cpdef string Phase_Tp(str Fluid, double T, double p):
    cdef bytes _Fluid = Fluid.encode('ascii')
    return _Phase_Tp(_Fluid,T,p)
    
cpdef string Phase_Trho(str Fluid, double T, double rho):
    cdef bytes _Fluid = Fluid.encode('ascii')
    return _Phase_Trho(_Fluid,T,rho)
    
cpdef string Phase(str Fluid, double T, double p):
    """
    Given a set of temperature and pressure, returns one of the following strings

    * Gas
    * Liquid
    * Supercritical
    * Two-Phase
    
    Phase diagram::
    
            |         |     
            |         |    Supercritical
            |         |
        p   | Liquid (b)------------
            |        /
            |       / 
            |      /       Gas
            |     / 
            |   (a)
            |  /
            |------------------------
    
                       T
    
           a: triple point
           b: critical point
           a-b: Saturation line
    """
    cdef bytes _Fluid = Fluid.encode('ascii')
    return _Phase(_Fluid,T,p)

cpdef double F2K(double T_F):
    """
    Convert temperature in degrees Fahrenheit to Kelvin
    """
    return _F2K(T_F)

cpdef double K2F(double T_K):
    """
    Convert temperature in Kelvin to degrees Fahrenheit
    """
    return _K2F(T_K)

cpdef list FluidsList():
    """
    Return a list of strings of all fluid names
    
    Returns
    -------
    FluidsList : list of strings of fluid names
        All the fluids that are included in CoolProp
    
    Notes
    -----
    
    Here is an example::
        
       In [0]: from CoolProp.CoolProp import FluidsList
    
       In [1]: FluidsList()
       
    """ 
    cdef str FL = _get_global_param_string("FluidsList")
    return FL.split(',')

cpdef get_aliases(str Fluid):
    """
    Return a comma separated string of aliases for the given fluid
    """
    cdef bytes _Fluid = Fluid.encode('ascii')
    return [F.encode('ascii') for F in (_get_fluid_param_string(_Fluid,'aliases').encode('ascii')).decode('ascii').split(',')]

cpdef get_ASHRAE34(str Fluid):
    """
    Return the safety code for the fluid from ASHRAE34 if it is in ASHRAE34
    """
    cdef bytes _Fluid = Fluid.encode('ascii')
    return _get_fluid_param_string(_Fluid,"ASHRAE34")
    
cpdef string get_REFPROPname(str Fluid):
    """
    Return the REFPROP compatible name for the fluid (only useful on windows)
    
    Some fluids do not use the REFPROP name.  For instance, 
    ammonia is R717, and propane is R290.  You can still can still call CoolProp
    using the name ammonia or R717, but REFPROP requires that you use a limited
    subset of names.  Therefore, this function that returns the REFPROP compatible
    name.  To then use this to call REFPROP, you would do something like::
    
       In [0]: from CoolProp.CoolProp import get_REFPROPname, Props
    
       In [1]: Fluid = 'REFPROP-' + get_REFPROPname('R290')
       
       In [2]: Props('D', 'T', 300, 'P', 300, Fluid)
    """
    cdef bytes _Fluid = Fluid.encode('ascii')
    return _get_fluid_param_string(_Fluid,'REFPROP_name')

cpdef string get_BibTeXKey(str Fluid, str key):
    """
    Return the BibTeX key for the given fluid.
    
    The possible keys are
    
    * ``EOS``
    * ``CP0``
    * ``VISCOSITY``
    * ``CONDUCTIVITY``
    * ``ECS_LENNARD_JONES``
    * ``ECS_FITS``
    * ``SURFACE_TENSION``
    
    BibTeX keys refer to the BibTeX file in the trunk/CoolProp folder
    
    Returns
    -------
    key, string
         empty string if Fluid not in CoolProp, "Bad key" if key is invalid
    """
    return _get_BibTeXKey(Fluid.encode('ascii'), key.encode('ascii'))

cpdef string get_errstr():
    """
    Return the current error string
    """
    return _get_global_param_string("errstring")

cpdef set_debug_level(int level):
    """
    Set the current debug level as integer in the range [0,10]
    
    Parameters
    ----------
    level : int
        If level is 0, no output will be written to screen, if >0, 
        some output will be written to screen.  The larger level is, 
        the more verbose the output will be
    """
    _set_debug_level(level)

cpdef get_debug_level():
    """
    Return the current debug level as integer
    
    Returns
    -------
    level : int
        If level is 0, no output will be written to screen, if >0, 
        some output will be written to screen.  The larger level is, 
        the more verbose the output will be
    """
    return _get_debug_level()
    
cpdef string get_CAS_code(string Fluid):
    """
    Return a string with the CAS number for the given fluid
    """
    return _get_fluid_param_string(Fluid,"CAS")
    
cpdef bint IsFluidType(string Fluid, string Type):
    """
    Check if a fluid is of a given type
    
    Valid types are:
    
    * ``Brine``
    * ``PseudoPure`` (or equivalently ``PseudoPureFluid``)
    * ``PureFluid``
    """
    cdef bytes _Fluid = Fluid.encode('ascii')
    cdef bytes _Type = Type.encode('ascii')
    if _IsFluidType(_Fluid,_Type):
        return True
    else:
        return False
    
cpdef bint set_TTSE_mode(char* FluidName, char* Value): 
    """ Set the mode of the TTSE table, one of ``"TTSE"`` or ``"BICUBIC"``
    """
    return _set_TTSE_mode(FluidName, Value)

cpdef str get_TTSE_mode(string fluid):
    """ Get the mode of the TTSE table, one of ``"TTSE"`` or ``"BICUBIC"``
    """
    return _get_fluid_param_string(fluid,'TTSE_mode').encode('ascii')

#: Enable the TTSE
cpdef bint enable_TTSE_LUT(char *FluidName): return _enable_TTSE_LUT(FluidName)
#: Check if TTSE is enabled
cpdef bint isenabled_TTSE_LUT(char *FluidName): return _isenabled_TTSE_LUT(FluidName)
#: Disable the TTSE
cpdef bint disable_TTSE_LUT(char *FluidName): return _disable_TTSE_LUT(FluidName)

#: Enable the TTSE
cpdef bint enable_TTSE_LUT_writing(char *FluidName): return _enable_TTSE_LUT_writing(FluidName)
#: Check if TTSE is enabled
cpdef bint isenabled_TTSE_LUT_writing(char *FluidName): return _isenabled_TTSE_LUT_writing(FluidName)
#: Disable the TTSE
cpdef bint disable_TTSE_LUT_writing(char *FluidName): return _disable_TTSE_LUT_writing(FluidName)

#: Over-ride the default size of both of the saturation LUT
cpdef bint set_TTSESat_LUT_size(char *FluidName, int N): return _set_TTSESat_LUT_size(FluidName, N)
#: Over-ride the default size of the single-phase LUT
cpdef bint set_TTSESinglePhase_LUT_size(char *FluidName, int Np, int Nh): return _set_TTSESinglePhase_LUT_size(FluidName, Np, Nh)
#: Over-ride the default range of the single-phase LUT
cpdef bint set_TTSESinglePhase_LUT_range(char *FluidName, double hmin, double hmax, double pmin, double pmax): return _set_TTSESinglePhase_LUT_range(FluidName, hmin, hmax, pmin, pmax)

cpdef tuple get_TTSESinglePhase_LUT_range(char *FluidName):
    """
    Get the current range of the single-phase LUT
    
    Returns
    -------
    tuple of hmin,hmax,pmin,pmax
    
    """
    cdef double hmin = 0, hmax = 0, pmin = 0, pmax = 0
    #In cython, hmin[0] to get pointer rather than &hmin
    cdef bint valsok = _get_TTSESinglePhase_LUT_range(FluidName, &hmin, &hmax, &pmin, &pmax)
    if valsok:
        return (hmin, hmax, pmin, pmax)
    else:
        raise ValueError("Either your FluidName was invalid or LUT bounds not available since no call has been made to tables")

cpdef tuple conformal_Trho(bytes_or_str Fluid, bytes_or_str ReferenceFluid, double T, double rho):
    """
    
    """    
    cdef double T0 = 0,rho0= 0
    _conformal_Trho(Fluid, ReferenceFluid, T, rho, &T0, &rho0)
    return T0,rho0

cpdef rhosatL_anc(bytes_or_str Fluid, double T):
    return _rhosatL_anc(Fluid,T)

cpdef rhosatV_anc(bytes_or_str Fluid, double T):
    return _rhosatV_anc(Fluid,T)

cpdef psatL_anc(bytes_or_str Fluid, double T):
    return _psatL_anc(Fluid,T)

cpdef psatV_anc(bytes_or_str Fluid, double T):
    return _psatV_anc(Fluid,T)

cpdef viscosity_residual(bytes_or_str Fluid, double T, double rho):
    return _viscosity_residual(Fluid, T, rho)

cpdef viscosity_dilute(bytes_or_str Fluid, double T):
    return _viscosity_dilute(Fluid,T)

cpdef conductivity_background(bytes_or_str Fluid, double T, double rho):
    return _conductivity_background(Fluid,T, rho)

cpdef conductivity_critical(bytes_or_str Fluid, double T, double rho):
    return _conductivity_critical(Fluid,T, rho)
    
cpdef set_standard_unit_system(int unit_system):
    _set_standard_unit_system(unit_system)
        
cpdef int get_standard_unit_system():
    return _get_standard_unit_system()
        
from math import pow as pow_

#A dictionary mapping parameter index to string for use with non-CoolProp fluids
cdef dict paras = {iD : 'D',
                   iQ : 'Q',
                   iMM : 'M',
                   iT : 'T',
                   iH : 'H',
                   iP : 'P',
                   iC : 'C',
                   iC0 : 'C0',
                   iO : 'O',
                   iV : 'V',
                   iL : 'L',
                   iS : 'S',
                   iU : 'U',
                   iDpdT : 'dpdT'}

cdef dict paras_inverse = {v:k for k,v in paras.iteritems()}

cdef class State:
    """
    A class that contains all the code that represents a thermodynamic state
    
    The motivation for this class is that it is useful to be able to define the
    state once using whatever state inputs you like and then be able to calculate
    other thermodynamic properties with the minimum of computational work.
    
    Let's suppose that you have inputs of pressure and temperature and you want
    to calculate the enthalpy and pressure.  Since the Equations of State are
    all explicit in temperature and density, each time you call something like::
    
        h = Props('H','T',T','P',P,Fluid)
        s = Props('S','T',T','P',P,Fluid)
        
    the solver is used to carry out the T-P flash calculation. And if you wanted
    entropy as well you could either intermediately calculate ``T``, ``rho`` and then use
    ``T``, ``rho`` in the EOS in a manner like::
    
        rho = Props('D','T',T','P',P,Fluid)
        h = Props('H','T',T','D',rho,Fluid)
        s = Props('S','T',T','D',rho,Fluid)
        
    Instead in this class all that is handled internally. So the call to update
    sets the internal variables in the most computationally efficient way possible
    """
        
    def __init__(self, str Fluid, dict StateDict, double xL=-1.0, object Liquid = None, object phase = None):
        """
        Parameters
        ----------
        Fluid, string
        StateDict, dictionary
            The state of the fluid - passed to the update function
        phase, string
            The phase of the fluid, it it is known.  One of ``Gas``,``Liquid``,``Supercritical``,``TwoPhase``
        xL, float
            Liquid mass fraction (not currently supported)
        Liquid, string
            The name of the liquid (not currently supported)
        """
        cdef bytes _Fluid = Fluid.encode('ascii')
        cdef bytes _Liquid
        
        if Fluid == 'none':
            return
        else:
            self.set_Fluid(Fluid)
        
        if Liquid is None:
            _Liquid = b''
        elif isinstance(Liquid,str):
            _Liquid = Liquid.encode('ascii')
        elif isinstance(Liquid,bytes):
            _Liquid = Liquid
        else:
            raise TypeError()
            
        if phase is None:
            _phase = b''
        elif isinstance(phase,str):
            _phase = phase.encode('ascii')
        elif isinstance(phase,bytes):
            _phase = phase
        else:
            raise TypeError()
        
        self.xL = xL
        self.Liquid = _Liquid
        self.phase = _phase
        #Parse the inputs provided
        self.update(StateDict)
        #Set the phase flag
        if self.phase == str('Gas') or self.phase == str('Liquid') or self.phase == str('Supercritical'):
            if self.is_CPFluid and (self.phase == str('Gas') or self.phase == str('Liquid')):
                self.PFC.CPS.flag_SinglePhase = True
            elif not self.is_CPFluid and self.phase is not None:
                _set_phase(self.phase)
            
    def __reduce__(self):
        d={}
        d['xL']=self.xL
        d['Liquid']=self.Liquid
        d['Fluid']=self.Fluid
        d['T']=self.T_
        d['rho']=self.rho_
        d['phase'] = self.phase
        return rebuildState,(d,)
          
    
        
    cpdef set_Fluid(self, str Fluid):
        self.Fluid = Fluid.encode('ascii')

        if Fluid.startswith('REFPROP-'):
            add_REFPROP_fluid(Fluid)
        self.iFluid = get_Fluid_index(Fluid)
        
        #  Try to get the fluid from CoolProp
        if self.iFluid >= 0:
            #  It is a CoolProp Fluid so we can use the faster integer passing function
            self.is_CPFluid = True
            #  Instantiate the C++ State class
            self.PFC = PureFluidClass(self.Fluid)
        else:
            #  It is not a CoolProp fluid, have to use the slower calls
            self.is_CPFluid = False
        
    cpdef update_ph(self, double p, double h):
        """
        Use the pressure and enthalpy directly
        
        Parameters
        ----------
        p: float
            Pressure (absolute) [kPa]
        h: float
            Enthalpy [kJ/kg]
        
        """
        self.p_ = p
        cdef double T
        
        if self.is_CPFluid:
            self.PFC.update(iP, p, iH, h)
            self.T_ = self.PFC.T()
            self.rho_ = self.PFC.rho()
        else:
            T = _Props('T','P',p,'H',h,self.Fluid)
            if abs(T)<1e90:
                self.T_=T
            else:
                errstr = _get_global_param_string('errstring')
                raise ValueError(errstr)
            self.rho_ = _Props('D','P',p,'H',h,self.Fluid)
            
    cpdef update_Trho(self, double T, double rho):
        """
        Just use the temperature and density directly for speed
        
        Parameters
        ----------
        T: float
            Temperature [K]
        rho: float
            Density [kg/m^3]
            
        """
        cdef double p
        self.T_ = T
        self.rho_ = rho
        
        if self.is_CPFluid:
            self.PFC.update(iT,T,iD,rho)
            p = self.PFC.p()
        else:
            p = _Props('P','T',T,'D',rho,self.Fluid)
        
        if abs(p)<1e90:
            self.p_ = p
        else:
            errstr = _get_global_param_string('errstring')
            raise ValueError(errstr)
        
    cpdef update(self, dict params, double xL=-1.0):
        """
        Parameters
        params, dictionary 
            A dictionary of terms to be updated, with keys equal to single-char inputs to the Props function,
            for instance ``dict(T=298, P = 101.325)`` would be one standard atmosphere
        """
            
        cdef double p
        cdef long iInput1, iInput2
        cdef bytes errstr
        
        # If no value for xL is provided, it will have a value of -1 which is 
        # impossible, so don't update xL
        if xL > 0:
            #There is liquid
            self.xL=xL
            self.hasLiquid=True
        else:
            #There's no liquid
            self.xL=0.0
            self.hasLiquid=False
        
        #Given temperature and pressure, determine density of gas 
        # (or gas and oil if xL is provided)
        if abs(self.xL)<=1e-15:
            
            if self.is_CPFluid:
                items = list(params.items())
                iInput1 = paras_inverse[items[0][0]]
                iInput2 = paras_inverse[items[1][0]]
                try: 
                    self.PFC.update(iInput1, items[0][1], iInput2, items[1][1])
                except:
                    raise
                self.T_ = self.PFC.T()
                self.p_ = self.PFC.p()
                self.rho_ = self.PFC.rho()
                return
            
            #Get the density if T,P provided, or pressure if T,rho provided
            if 'P' in params:
                self.p_=params['P']
                rho = _Props('D','T',self.T_,'P',self.p_,self.Fluid)
                
                if abs(rho) < 1e90:
                    self.rho_=rho
                else:
                    errstr = _get_global_param_string('errstring')
                    raise ValueError(errstr)
            elif 'D' in params:
                self.rho_=params['D']
                p = _Props('P','T',self.T_,'D',self.rho_,self.Fluid)
                
                if abs(p)<1e90:
                    self.p_=p
                else:
                    errstr = _get_global_param_string('errstring')
                    raise ValueError(errstr+str(params))
            elif 'Q' in params:
                p = _Props('P','T',self.T_,'Q',params['Q'],self.Fluid)
                self.rho_ = _Props('D','T',self.T_,'Q',params['Q'],self.Fluid)
                
                if abs(self.rho_)<1e90:
                    pass
                else:
                    errstr = _get_global_param_string('errstring')
                    raise ValueError(errstr+str(params))
            else:
                raise KeyError("Dictionary must contain the key 'T' and one of 'P' or 'D'")
            
        elif self.xL>0 and self.xL<=1:
            raise ValueError('xL is out of range - value for xL is [0,1]')
        else:
            raise ValueError('xL must be between 0 and 1')
        
    cpdef long Phase(self) except *:
        """
        Returns an integer flag for the phase of the fluid, where the flag value
        is one of iLiquid, iSupercritical, iGas, iTwoPhase
        
        These constants are defined in the phase_constants module, and are imported
        into this module
        """
        
        if self.is_CPFluid:
            return self.PFC.phase()
        else:
            raise NotImplementedError("Phase not defined for fluids other than CoolProp fluids")
        
    cpdef double Props(self, long iOutput) except *: 
        if iOutput<0:
            raise ValueError('Your output is invalid') 
        
        if self.is_CPFluid:
            return self.PFC.keyed_output(iOutput)
        else:
            return _Props(paras[iOutput],'T',self.T_,'D',self.rho_,self.Fluid)
            
    cpdef double get_Q(self) except *:
        """ Get the quality [-] """
        return self.Props(iQ)
    property Q:
        """ The quality [-] """
        def __get__(self):
            return self.get_Q()
    
    cpdef double get_MM(self) except *:
        """ Get the mole mass [kg/kmol] or [g/mol] """
        return self.Props(iMM)
    
    cpdef double get_rho(self) except *:
        """ Get the density [kg/m^3] """ 
        return self.Props(iD)
    property rho:
        """ The density [kg/m^3] """
        def __get__(self):
            return self.Props(iD)
            
    cpdef double get_p(self) except *:
        """ Get the pressure [kPa] """ 
        return self.Props(iP)
    property p:
        """ The pressure [kPa] """
        def __get__(self):
            return self.get_p()
    
    cpdef double get_T(self) except *: 
        """ Get the temperature [K] """
        return self.Props(iT)
    property T:
        """ The temperature [K] """
        def __get__(self):
            return self.get_T()
    
    cpdef double get_h(self) except *: 
        """ Get the specific enthalpy [kJ/kg] """
        return self.Props(iH)
    property h:
        """ The specific enthalpy [kJ/kg] """
        def __get__(self):
            return self.get_h()
          
    cpdef double get_u(self) except *: 
        """ Get the specific internal energy [kJ/kg] """
        return self.Props(iU)
    property u:
        """ The internal energy [kJ/kg] """
        def __get__(self):
            return self.get_u()
            
    cpdef double get_s(self) except *: 
        """ Get the specific enthalpy [kJ/kg/K] """
        return self.Props(iS)
    property s:
        """ The specific enthalpy [kJ/kg/K] """
        def __get__(self):
            return self.get_s()
    
    cpdef double get_cp0(self) except *:
        """ Get the specific heat at constant pressure for the ideal gas [kJ/kg/K] """
        return self.Props(iC0)
    
    cpdef double get_cp(self) except *: 
        """ Get the specific heat at constant pressure  [kJ/kg/K] """
        return self.Props(iC)
    property cp:
        """ The specific heat at constant pressure  [kJ/kg/K] """
        def __get__(self):
            return self.get_cp()
            
    cpdef double get_cv(self) except *: 
        """ Get the specific heat at constant volume  [kJ/kg/K] """
        return self.Props(iO)
    property cv:
        """ The specific heat at constant volume  [kJ/kg/K] """
        def __get__(self):
            return self.get_cv()
        
    cpdef double get_speed_sound(self) except *: 
        """ Get the speed of sound  [m/s] """
        return self.Props(iA)
            
    cpdef double get_visc(self) except *:
        """ Get the viscosity, in [Pa-s]"""
        return self.Props(iV)
    property visc:
        """ The viscosity, in [Pa-s]"""
        def __get__(self):
            return self.get_visc()

    cpdef double get_cond(self) except *:
        """ Get the thermal conductivity, in [kW/m/K]"""
        return self.Props(iL)
    property k:
        """ The thermal conductivity, in [kW/m/K]"""
        def __get__(self):
            return self.get_cond()
        
    cpdef double get_Tsat(self, double Q = 1):
        """ 
        Get the saturation temperature, in [K]
        
        Returns ``None`` if pressure is not within the two-phase pressure range 
        """
        import CoolProp as CP
        if self.p_ > CP.Props(self.Fluid,'pcrit') or self.p_ < CP.Props(self.Fluid,'ptriple'):
            return None 
        else:
            return CP.Props('T', 'P', self.p_, 'Q', Q, self.Fluid)
    property Tsat:
        """ The saturation temperature (dew) for the given pressure, in [K]"""
        def __get__(self):
            return self.get_Tsat(1)
        
    cpdef double get_superheat(self):
        """ 
        Get the amount of superheat above the saturation temperature corresponding to the pressure, in [K]
        
        Returns ``None`` if pressure is not within the two-phase pressure range 
        """
        
        Tsat = self.get_Tsat(1) #dewpoint temp
        
        if Tsat is not None:
            return self.T_-Tsat
        else:
            return None
    property superheat:
        """ 
        The amount of superheat above the saturation temperature corresponding to the pressure, in [K]
        
        Returns ``None`` if pressure is not within the two-phase pressure range 
        """
        def __get__(self):    
            return self.get_superheat()
        
    cpdef double get_subcooling(self):
        """ 
        Get the amount of subcooling below the saturation temperature corresponding to the pressure, in [K]
        
        Returns ``None`` if pressure is not within the two-phase pressure range 
        """
        
        Tsat = self.get_Tsat(0) #bubblepoint temp
        
        if Tsat is not None:
            return Tsat - self.T_
        else:
            return None
    property subcooling:
        """ 
        The amount of subcooling below the saturation temperature corresponding to the pressure, in [K]
        
        Returns ``None`` if pressure is not within the two-phase pressure range 
        """
        def __get__(self):    
            return self.get_subcooling()
            
    property Prandtl:
        """ The Prandtl number (cp*mu/k) [-] """
        def __get__(self):
            return self.cp * self.visc / self.k
            
    cpdef double get_dpdT(self) except *:
        if self.is_CPFluid:
            return self.PFC.dpdT_constrho()
        else:
            raise ValueError("get_dpdT not supported for fluids that are not in CoolProp")
    property dpdT:
        def __get__(self):
            return self.get_dpdT()
        
    cpdef speed_test(self, int N):
        from time import clock
        cdef int i
        cdef char * k
        cdef long ikey
        cdef string Fluid = self.Fluid
        cdef long IT = 'T'
        cdef long ID = 'D'
        import CoolProp as CP
        
        print 'Call to the Python call layer (CoolProp.CoolProp.Props)'
        print "'M' involves basically no computational effort and is a good measure of the function call overhead"
        keys = ['H','P','S','U','C','O','V','L','M','C0','dpdT']
        for key in keys:
            t1=clock()
            for i in range(N):
                CP.Props(key,'T',self.T_,'D',self.rho_,Fluid)
            t2=clock()
            print 'Elapsed time for {0:d} calls for "{1:s}" at {2:g} us/call'.format(N,key,(t2-t1)/N*1e6)
            
        print 'Direct c++ call to CoolProp without the Python call layer (_Props function)'
        print "'M' involves basically no computational effort and is a good measure of the function call overhead"
        keys = ['H','P','S','U','C','O','V','L','M','C0','dpdT']
        for key in keys:
            t1=clock()
            for i in range(N):
                _Props(key,'T',self.T_,'D',self.rho_,Fluid)
            t2=clock()
            print 'Elapsed time for {0:d} calls for "{1:s}" at {2:g} us/call'.format(N,key,(t2-t1)/N*1e6)
        
        print 'Call to the c++ layer through IProps'
        keys = [iH,iP,iS,iU,iC,iO,iV,iL,iMM,iC0,iDpdT]
        for key in keys:
            t1=clock()
            for i in range(N):
                _IProps(key,iT,self.T_,iD,self.rho_,self.iFluid)
            t2=clock()
            print 'Elapsed time for {0:d} calls for "{1:s}" at {2:g} us/call'.format(N,paras[key],(t2-t1)/N*1e6)
            
        print 'Call to the c++ layer using integers'
        keys = [iH,iP,iS,iU,iC,iO,iV,iL,iMM,iC0,iDpdT]
        for key in keys:
            t1=clock()
            for i in range(N):
                self.PFC.update(iT,self.T_,iD,self.rho_)
                self.PFC.keyed_output(key)
            t2=clock()
            print 'Elapsed time for {0:d} calls for "{1:s}" at {2:g} us/call'.format(N,paras[key],(t2-t1)/N*1e6)
        
        keys = [iH,iP,iS,iU,iC,iO,iV,iL,iMM,iC0,iDpdT]
        isenabled = _isenabled_TTSE_LUT(<bytes>Fluid)
        _enable_TTSE_LUT(<bytes>Fluid)
        _IProps(iH,iT,self.T_,iD,self.rho_,self.iFluid)
        
        print 'Call using TTSE with T,rho'
        print "'M' involves basically no computational effort and is a good measure of the function call overhead"
        for ikey in keys:
            t1=clock()
            self.PFC.update(iT,self.T_,iD,self.rho_)
            for i in range(N):
                self.PFC.keyed_output(ikey)
            t2=clock()
            print 'Elapsed time for {0:d} calls for "{1:s}" at {2:g} us/call'.format(N,paras[ikey],(t2-t1)/N*1e6)
            
        print 'Call using TTSE with p,h'
        print "'M' involves basically no computational effort and is a good measure of the function call overhead"
        cdef double hh = self.h
        for ikey in keys:
            t1=clock()
            self.PFC.update(iP,self.p_,iH,hh)
            for i in range(N):
                self.PFC.keyed_output(ikey)
            t2=clock()
            print 'Elapsed time for {0:d} calls for "{1:s}" at {2:g} us/call'.format(N,paras[ikey],(t2-t1)/N*1e6)
        
        print 'Using CoolPropStateClass with T,rho with LUT'
        keys = [iH,iP,iC,iO,iDpdT]
        t1=clock()
        for i in range(N):
            self.PFC.update(iT,self.T_,iD,self.rho_)
            for ikey in keys:
                self.PFC.keyed_output(ikey)
        t2=clock()
        print 'Elapsed time for {0:d} calls of iH,iP,iC,iO,iDpdT takes {1:g} us/call'.format(N,(t2-t1)/N*1e6)
        
        if not isenabled:
            _disable_TTSE_LUT(<bytes>Fluid)
    
    def __str__(self):
        """
        Return a string representation of the state
        """
        units={'T': 'K', 
               'p': 'kPa', 
               'rho': 'kg/m^3',
               'Q':'kg/kg',
               'h':'kJ/kg',
               'u':'kJ/kg',
               's':'kJ/kg/K',
               'visc':'Pa-s',
               'k':'kW/m/K',
               'cp':'kJ/kg/K',
               'cv':'kJ/kg/K',
               'dpdT':'kPa/K',
               'Tsat':'K',
               'superheat':'K',
               'subcooling':'K',
        }
        s='phase = '+self.phase+'\n'
        for k in ['T','p','rho','Q','h','u','s','visc','k','cp','cv','dpdT','Prandtl','superheat','subcooling']:
            if k in units:
                s+=k+' = '+str(getattr(self,k))+' '+units[k]+'\n'
            else:
                s+=k+' = '+str(getattr(self,k))+' NO UNITS'+'\n'
        return s.rstrip()
        
    cpdef State copy(self):
        """
        Make a copy of this State class
        """
        cdef State S = State.__new__(State)
        S.set_Fluid(str(self.Fluid.decode('ascii')))
        S.update_Trho(self.T_, self.rho_)
        S.phase = self.phase
        return S
    
def rebuildState(d):
    S=State(d['Fluid'],{'T':d['T'],'D':d['rho']},phase=d['phase'])
    S.xL = d['xL']
    S.Liquid=d['Liquid']
    return S
    
