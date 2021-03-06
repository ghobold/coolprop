#define CATCH_CONFIG_RUNNER
#include "Catch/catch.hpp"
#include "Tests.h"
#include "CoolPropDLL.h"
#include "CoolProp.h"

TEST_CASE( "Check reference state", "[reference_state]" ) 
{
	SECTION("IIR")
	{
		set_reference_stateS("Propane","IIR");
		double h_EOS = PropsSI("H","T",273.15,"Q",0,"Propane");
		double s_EOS = PropsSI("S","T",273.15,"Q",0,"Propane");
		double h_target = 200000;
		double s_target = 1000;

		REQUIRE(abs(h_target-h_EOS) < 1e-6);
		REQUIRE(abs(s_target-s_EOS) < 1e-6);
	}
	SECTION("NBP")
	{
		set_reference_stateS("Propane","NBP");
		double h_EOS = PropsSI("H","P",101325,"Q",0,"Propane");
		double s_EOS = PropsSI("S","P",101325,"Q",0,"Propane");
		double h_target = 0;
		double s_target = 0;

		REQUIRE(abs(h_target-h_EOS) < 1e-6);
		REQUIRE(abs(s_target-s_EOS) < 1e-6);
	}
	SECTION("ASHRAE")
	{
		set_reference_stateS("Propane","ASHRAE");
		double h_EOS = PropsSI("H","T",233.15,"Q",0,"Propane");
		double s_EOS = PropsSI("S","T",233.15,"Q",0,"Propane");
		double h_target = 0;
		double s_target = 0;

		REQUIRE(abs(h_target-h_EOS) < 1e-6);
		REQUIRE(abs(s_target-s_EOS) < 1e-6);
	}
}

static Catch::Session session; // There must be exactly once instance

int run_fast_tests()
{
	char* const argv[] = {"/a/dummy/path","[fast]"};
	int returnCode = session.applyCommandLine(2, argv);
    if( returnCode != 0 ) // Indicates a command line error
	{
		return returnCode;
	}
	return session.run();
}

int run_not_slow_tests()
{
	char* const argv[] = {"/a/dummy/path","~[slow]"};
	int returnCode = session.applyCommandLine(2, argv);
    if( returnCode != 0 ) // Indicates a command line error
	{
		return returnCode;
	}
	time_t t1, t2;
	t1 = clock();
	session.run();
	t2 = clock();
	printf("Elapsed time for not slow tests: %g s",(double)(t2-t1)/CLOCKS_PER_SEC);

	return 1;
}

void run_tests()
{
	session.run();
}