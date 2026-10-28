package vd;

import android.app.ActivityOptions;
import android.content.Context;
import android.content.Intent;
import android.graphics.PixelFormat;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.media.Image;
import android.media.ImageReader;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;

import java.io.File;
import java.io.FileWriter;

public class VdMain {
    static final int W = 720, H = 1280, DPI = 320;
    static final String BASE = "/data/local/tmp";
    static final String NAME = "minivd";
    static volatile int frames = 0;

    public static void main(final String[] args) {
        Context ctx = null;
        try {
            Looper.prepareMainLooper();
            Class<?> at = Class.forName("android.app.ActivityThread");
            Object thread = at.getMethod("systemMain").invoke(null);
            Context sys = (Context) at.getMethod("getSystemContext").invoke(thread);
            try {
                ctx = sys.createPackageContext("com.android.shell",
                        Context.CONTEXT_INCLUDE_CODE | Context.CONTEXT_IGNORE_SECURITY);
                System.out.println("SHELL_CTX_OK " + ctx.getPackageName());
            } catch (Throwable e) {
                System.out.println("SHELL_CTX_FAIL " + e);
                ctx = sys;
            }
        } catch (Throwable t) {
            System.out.println("CTX_FAIL " + t);
            t.printStackTrace(System.out);
        }
        final Context fctx = ctx;
        Thread t = new Thread(new Runnable() {
            public void run() {
                try {
                    work(fctx, args);
                } catch (Throwable e) {
                    System.out.println("FATAL: " + e);
                    e.printStackTrace(System.out);
                }
            }
        });
        t.start();
        Looper.loop();
    }

    static void work(Context ctx, String[] args) throws Exception {
        if (ctx == null) return;
        DisplayManager dm = (DisplayManager) ctx.getSystemService(Context.DISPLAY_SERVICE);
        ImageReader reader = ImageReader.newInstance(W, H, PixelFormat.RGBA_8888, 3);
        HandlerThread ht = new HandlerThread("img");
        ht.start();
        reader.setOnImageAvailableListener(new ImageReader.OnImageAvailableListener() {
            public void onImageAvailable(ImageReader r) {
                Image img = null;
                try {
                    img = r.acquireLatestImage();
                    if (img != null) frames++;
                } catch (Throwable e) {
                } finally {
                    if (img != null) img.close();
                }
            }
        }, new Handler(ht.getLooper()));

        VirtualDisplay vd = dm.createVirtualDisplay(NAME, W, H, DPI,
                reader.getSurface(),
                DisplayManager.VIRTUAL_DISPLAY_FLAG_PUBLIC
                        | DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY,
                null, null);
        int id = vd.getDisplay().getDisplayId();
        System.out.println("VD_CREATED id=" + id);

        boolean serve = args.length > 0 && "--serve".equals(args[0]);
        if (serve) {
            FileWriter fw = new FileWriter(BASE + "/vdisplay.state");
            fw.write("display=" + id + "\npid=" + android.os.Process.myPid() + "\n");
            fw.close();
            System.out.println("VD_READY display=" + id);
            File stop = new File(BASE + "/vdisplay.stop");
            while (!stop.exists()) {
                Thread.sleep(500);
            }
            stop.delete();
            vd.release();
            File st = new File(BASE + "/vdisplay.state");
            st.delete();
            System.out.println("VD_STOPPED");
            return;
        }

        if (args.length >= 2) {
            Intent i = new Intent(Intent.ACTION_MAIN).setClassName(args[0], args[1])
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            Bundle b = ActivityOptions.makeBasic().setLaunchDisplayId(id).toBundle();
            try {
                ctx.startActivity(i, b);
                System.out.println("LAUNCH_OK " + args[0] + "/" + args[1]);
            } catch (Throwable e) {
                System.out.println("LAUNCH_FAIL " + e);
            }
        }
        for (int s = 0; s < 300; s++) {
            Thread.sleep(1000);
            if (s % 15 == 0) System.out.println("ALIVE t=" + s + " frames=" + frames);
        }
        vd.release();
        System.out.println("DONE");
    }
}
