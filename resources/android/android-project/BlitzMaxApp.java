
//${start.app.package}
package com.blitzmax.android;
//${end.app.package}
import org.libsdl.app.SDLActivity;

public class BlitzMaxApp extends SDLActivity {

   static {
//${start.lib.imports}
//${end.lib.imports}
        System.loadLibrary( "${app.id}");
    }

}


