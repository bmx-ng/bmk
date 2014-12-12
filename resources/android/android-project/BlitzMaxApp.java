
//${start.app.package}
package com.blitzmax.android;
//${end.app.package}
import org.libsdl.app.SDLActivity;

public class BlitzMaxApp extends SDLActivity {

   static {
        System.loadLibrary( "${app.id}");
//${start.lib.imports}
//${end.lib.imports}
    }

}


