REM ******** set the variables ************
call "C:\Program Files (x86)\Microsoft Visual Studio 9.0\VC\vcvarsall.bat"
call "C:\Program Files\Microsoft Visual Studio 9.0\VC\vcvarsall.bat"

copy ..\..\..\wrappers\C#\Example.cs
erase *_wrap.cpp

swig.exe -csharp -dllimport "CoolProp" -c++ -outcurrentdir ../../../CoolProp/CoolProp.i
cl /c /I../../../CoolProp /EHsc CoolProp_wrap.cxx

REM ******* compile all the sources ***************
cl /c /I../../../CoolProp /EHsc ../../../CoolProp/*.cpp
link /DLL CoolProp_wrap.obj *.obj /OUT:CoolProp.dll

erase *.obj
erase CoolProp_wrap.cxx
erase CoolProp.lib
erase CoolProp.exp

call "C:\Program Files (x86)\Microsoft Visual Studio 10.0\VC\vcvarsall.bat"
csc *.cs /platform:x86
call Example > Output.txt

REM cleanup
erase *.cs
erase Example.exe
erase CoolProp.dll
copy ..\..\..\wrappers\C#\Example.cs