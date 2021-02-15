/*
License (MIT)

Copyright © 2016 Edin Mujkanovic

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and
to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of
the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

package com.exelerus.cordova.audioinputcapture;

import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CallbackContext;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.lang.ref.WeakReference;
import java.lang.System;
import java.io.File;
import java.net.URI;
import java.net.URISyntaxException;
import android.os.Handler;
import android.os.Message;
import android.util.Log;
import android.content.pm.PackageManager;
import org.apache.cordova.PermissionHelper;
import android.Manifest;


public class AudioInputCapture extends CordovaPlugin
{
    private static final String LOG_TAG = "AudioInputCapture";

    private CallbackContext initializeCallbackContext = null;
    private CallbackContext recordCallbackContext = null;
    private CallbackContext stopCallbackContext = null;
    private CallbackContext getPermissionCallbackContext = null;
    private AudioInputReceiver receiver;
    private final AudioInputCaptureHandler handler = new AudioInputCaptureHandler(this);

    public static String[]  permissions = { Manifest.permission.RECORD_AUDIO };
    public static int       RECORD_AUDIO = 0;
    public static final int PERMISSION_DENIED_ERROR = 20;
    public static final int INVALID_URL_ERROR = 30;
    public static final int INVALID_STATE_ERROR = 40;

    private boolean initialized = false;
    private int sampleRate = 44100;
    private int bufferSize = 4096;
    private int channels = 1;
    private String format = null;
    private int audioSource = 0;
    private URI fileUrl = null;
   
    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
        if (action.equals("initialize")) {
			try {
                Log.d(LOG_TAG, "initialize...");
				this.sampleRate = args.getInt(0);
				this.bufferSize = args.getInt(1);
				this.channels = args.getInt(2);
				this.format = args.getString(3);
				this.audioSource = args.getInt(4);

				if (args.isNull(5))  {
					this.fileUrl = null;
				}
				else {
					String fileUrlString = args.getString(5);
                    Log.d(LOG_TAG, "initialized with file: " + fileUrlString);
					this.fileUrl = new URI(fileUrlString);
					// Ensure it's a file URL
					File file = new File(this.fileUrl);
					if (file.exists() == true) {
						file.delete();
					}
				}
			}
			catch (URISyntaxException e) { // Not a valid URL
                Log.e(LOG_TAG, e.getMessage(), e);
				if (receiver != null) receiver.interrupt();
				this.fileUrl = null;
				callbackContext.sendPluginResult(
                    new PluginResult(PluginResult.Status.ERROR, INVALID_URL_ERROR));

				return false;
			}
			catch (IllegalArgumentException e) { // Not a file URL
                Log.e(LOG_TAG, e.getMessage(), e);
				if (receiver != null) receiver.interrupt();
				callbackContext.sendPluginResult(
                    new PluginResult(PluginResult.Status.ERROR, INVALID_URL_ERROR));
				return false;
			}
			catch (Exception e) {
                Log.e(LOG_TAG, e.getMessage(), e);
				if (receiver != null) receiver.interrupt();
				callbackContext.sendPluginResult(
                    new PluginResult(PluginResult.Status.ERROR, PERMISSION_DENIED_ERROR));
				return false;
			}

            // Invoke callback
            PluginResult result = new PluginResult(PluginResult.Status.OK);
            callbackContext.sendPluginResult(result);
            return true;
        }

		if (action.equals("checkMicrophonePermission")) {
			if(PermissionHelper.hasPermission(this, permissions[RECORD_AUDIO])) {
				PluginResult result = new PluginResult(PluginResult.Status.OK, Boolean.TRUE);
				callbackContext.sendPluginResult(result);
			}
			else {
				PluginResult result = new PluginResult(PluginResult.Status.OK, Boolean.FALSE);
				callbackContext.sendPluginResult(result);
			}

			return true;
		}
	
		if (action.equals("getMicrophonePermission") || action.equals("prepareToRecord")) {
			if (PermissionHelper.hasPermission(this, permissions[RECORD_AUDIO])) {
				PluginResult result = new PluginResult(PluginResult.Status.OK, Boolean.TRUE);
				callbackContext.sendPluginResult(result);
			}
			else {
				// Save context for when we know whether they've given permission
				this.getPermissionCallbackContext = callbackContext;

				// Return nothing in particular for now...
				PluginResult pluginResult = new PluginResult(PluginResult.Status.NO_RESULT);
				pluginResult.setKeepCallback(true);
				callbackContext.sendPluginResult(pluginResult);

				// Ask for permission.
				getMicPermission(RECORD_AUDIO);
			}

			return true;
		}

        if (action.equals("record")) {
			this.recordCallbackContext = callbackContext;
            promptForRecord();
			// Don't return any result now, since status results will be sent when events come in from broadcast receiver
			PluginResult pluginResult = new PluginResult(PluginResult.Status.NO_RESULT);
			pluginResult.setKeepCallback(true);
			callbackContext.sendPluginResult(pluginResult);
			return true;
        }

		if (action.equals("stop")) {
			if (receiver != null)
			{
                this.stopCallbackContext = callbackContext;
				receiver.interrupt();

                Log.d(LOG_TAG, "waiting for receiver thread to stop...");
                try {
                    receiver.join();
                    Log.d(LOG_TAG, "receiver thread stopped.");
                }
                catch (InterruptedException e) {
                    Log.e(LOG_TAG, e.getMessage(), e);
                }

                PluginResult pluginResult = new PluginResult(PluginResult.Status.NO_RESULT);
                pluginResult.setKeepCallback(true);
                callbackContext.sendPluginResult(pluginResult);

				return true;
			}
			else
			{
                // Not recording, so can't stop
				callbackContext.sendPluginResult(new PluginResult(PluginResult.Status.ERROR, INVALID_STATE_ERROR));
				return false;
			}
		}

        if (action.equals("forceSpeaker")) {
            // not needed on android
            PluginResult result = new PluginResult(PluginResult.Status.OK, Boolean.TRUE);
            callbackContext.sendPluginResult(result);
            return true;
        }

        if (action.equals("deviceCurrentTime")) {
            PluginResult result = new PluginResult(PluginResult.Status.OK, System.currentTimeMillis());
            callbackContext.sendPluginResult(result);
            return true;
        }

        if (action.equals("recordAtTime")) {
            PluginResult result = new PluginResult(PluginResult.Status.OK, Boolean.TRUE);
            callbackContext.sendPluginResult(result);
            return true;
        }

        if (action.equals("recordForDuration")) {
            PluginResult result = new PluginResult(PluginResult.Status.OK, Boolean.TRUE);
            callbackContext.sendPluginResult(result);
            return true;
        }

        if (action.equals("recordAtTimeForDuration")) {
            PluginResult result = new PluginResult(PluginResult.Status.OK, Boolean.TRUE);
            callbackContext.sendPluginResult(result);
            return true;
        }

        if (action.equals("pause")) {
            PluginResult result = new PluginResult(PluginResult.Status.OK, Boolean.TRUE);
            callbackContext.sendPluginResult(result);
            return true;
        }

        if (action.equals("deleteRecording")) {
            File file = new File(this.fileUrl);
            if (file.exists() == true) {
                file.delete();
            }
            PluginResult result = new PluginResult(PluginResult.Status.OK, Boolean.TRUE);
            callbackContext.sendPluginResult(result);
            return true;
        }

        return false;
    }

    public void onDestroy() {
        if (receiver != null && !receiver.isInterrupted()) {
            receiver.interrupt();
        }
    }

    public void onReset() {
        if (receiver != null && !receiver.isInterrupted()) {
            receiver.interrupt();
        }
    }

    /**
     * Create a new plugin result and send it back to JavaScript
     */
    private void sendUpdate(JSONObject info, boolean keepCallback) {
        if (this.recordCallbackContext != null) {
            PluginResult result = new PluginResult(PluginResult.Status.OK, info);
            result.setKeepCallback(keepCallback);
            this.recordCallbackContext.sendPluginResult(result);
            if (keepCallback == false) {
                this.recordCallbackContext = null;
            }
        }
        if (this.stopCallbackContext != null) {
            PluginResult result = new PluginResult(PluginResult.Status.OK, this.fileUrl != null ? fileUrl.toString() : "");
            result.setKeepCallback(keepCallback);
            this.stopCallbackContext.sendPluginResult(result);
            if (keepCallback == false) {
                this.stopCallbackContext = null;
            }
        }
    }

    private static class AudioInputCaptureHandler extends Handler {
        private final WeakReference<AudioInputCapture> mActivity;

        public AudioInputCaptureHandler(AudioInputCapture activity) {
            mActivity = new WeakReference<AudioInputCapture>(activity);
        }

        @Override
        public void handleMessage(Message msg) {
            Log.d(LOG_TAG, "message received from the recorder...");
            AudioInputCapture activity = mActivity.get();
            if (activity != null) {
                // Log.d(LOG_TAG, "activity: " + (activity.fileUrl != null ? activity.fileUrl.toString() : "null") + " > " + msg.getData().getString("file"));
                JSONObject info = new JSONObject();

                try {
                    info.put("data", msg.getData().getString("data"));
                }
                catch (JSONException e) {
                    Log.e(LOG_TAG, e.getMessage(), e);
                }

                try {
                    info.put("error", msg.getData().getString("error"));
                }
                catch (JSONException e) {
                    Log.e(LOG_TAG, e.getMessage(), e);
                }

				if (activity.fileUrl != null) {
				   try {
				      info.put("file", msg.getData().getString("file"));
				      activity.sendUpdate(info, false); // Release status callback in JS side
				      // activity.recordCallbackContext = null;
				   }
				   catch (JSONException e) {
				      Log.e(LOG_TAG, e.getMessage(), e);
				   }
				}
				else {
				   activity.sendUpdate(info, false);
                   // activity.recordCallbackContext = null;
				}
            }
        }
    }

    /**
     * Prompt user for record audio permission
     */
    protected void getMicPermission(int requestCode) {
        PermissionHelper.requestPermission(this, requestCode, permissions[RECORD_AUDIO]);
    }

    /**
     * Ensure that we have gotten record audio permission
     */
    private void promptForRecord() {
		// If we've already got a receiver, stop it
		if (receiver != null) receiver.interrupt();

		if (PermissionHelper.hasPermission(this, permissions[RECORD_AUDIO])) {
			receiver = new AudioInputReceiver(this.sampleRate, this.bufferSize, this.channels, this.format, this.audioSource, this.fileUrl);
			receiver.setHandler(handler);
			receiver.start();
            PluginResult result = new PluginResult(PluginResult.Status.OK, this.fileUrl != null ? fileUrl.toString() : "");
            this.recordCallbackContext.sendPluginResult(result);
            this.recordCallbackContext = null;
		}
		else {
			getMicPermission(RECORD_AUDIO);
		}
    }

    /**
     * Handle request permission result
     */
    public void onRequestPermissionResult(int requestCode, String[] permissions,
                                              int[] grantResults) throws JSONException {
       
        for (int r:grantResults) {
			if (r == PackageManager.PERMISSION_DENIED) {
				if (this.recordCallbackContext != null) {
					// Called directly from "record"
					this.recordCallbackContext.sendPluginResult(
                        new PluginResult(PluginResult.Status.ERROR, PERMISSION_DENIED_ERROR));
                    this.recordCallbackContext = null;
					return;
				}
				else if (this.getPermissionCallbackContext != null) { // Called from "getMicrophonePermission"
					PluginResult result = new PluginResult(PluginResult.Status.OK, Boolean.FALSE);
					this.getPermissionCallbackContext.sendPluginResult(result);
                    this.getPermissionCallbackContext = null;
				}
			}
        }

		if (this.recordCallbackContext != null) {
			// Called directly from "record"
		    promptForRecord();
		}
		else if (this.getPermissionCallbackContext != null) { // Called from "getMicrophonePermission"
			PluginResult result = new PluginResult(PluginResult.Status.OK, Boolean.TRUE);
			this.getPermissionCallbackContext.sendPluginResult(result);
            this.getPermissionCallbackContext = null;
		}
    }
}
