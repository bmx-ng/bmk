BMK (NG) INSTRUCTIONS
=====================

Always backup before deploying a new BMK. (Better safe than sorry!)


Compiling BMK
-------------

bmk.bmx is the main source-file.

BMK should be compiled in Non-GUI and Release mode. 

You can also compile BMK in either Threaded or Non-threaded modes.

When compiled with Threading enabled, BMK will parallel compile C/C++ files
when it can, scaling to the number of available cores on your system.
Note : The compiled executable filename will include ".mt", which you will need
to remove when deploying it in BlitzMax/bin.

When compiled without Threading, BMK will compile all files, one at a time.


Deploying BMK
-------------

The bmk executable, core.bmk and make.bmk, should be deployed in the BlitzMax/bin
folder.


You can also create a custom.bmk file in BlitzMax/bin which is used to override built-in
compiler options, such as optimisations. (see "Using custom.bmk" below)


On Linux and MacOS systems, you may also optionally deploy config.bmk. This provides
settings for Cross-Compiling modules and applications for Win32 targets. If you intend
to use this, please check the file for any system-specific configuration options you
need to supply.



Using custom.bmk
----------------

This file allows you to override the default compiler options BMK uses.

The format is :

<command> <name> <value>


The normal command is "addccopt", but all valid commands are listed here :

    addccopt             - for all platforms and processors
    addlinuxccopt        - Linux specific option
    addwin32ccopt        - Win32 specific option
    addmacccopt          - MacOS specific option
    addmacx86ccopt       - MacOS x86 specific option
    addmacppcccopt       - MacOS ppc specific option

The following option names will override the default settings appropriately

 optimization            - Optimize level. The default is -Os (optimize for size)
 arch                    - The processor architecture. The default -march=pentium
 math                    - The floating point unit.


If you want a value to contain spaces, wrap it in double-quotes (")

See the gcc manual for more options. (hint: google for "man gcc", is useful).



Cross-Compiling
---------------

BMK supports compiling of Win32 binaries and modules on MacOS and Linux systems.

You can download all the necessary packages from the following location : 

        http://brucey.net/programming/blitz/mingw/



Running BMK
-----------

You can obtain the current version of BMK with :

    bmk -v


Running BMK with no options will produce a basic Usage guide.

