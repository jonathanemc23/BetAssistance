// Google sign-in for the web app, through Firebase Authentication's popup.
// Firebase's script is only downloaded the first time someone taps
// "Continue with Google". The app keeps the session itself (lib/data/
// account.dart), so Firebase is told not to store one here.
(function () {
  var version = '10.14.1';
  var ready = null;
  var loaded = false;

  function load(src) {
    return new Promise(function (resolve, reject) {
      var s = document.createElement('script');
      s.src = src;
      s.onload = resolve;
      s.onerror = function () { reject({ code: 'load' }); };
      document.head.appendChild(s);
    });
  }

  function setUp(apiKey, project) {
    return load('https://www.gstatic.com/firebasejs/' + version + '/firebase-app-compat.js')
      .then(function () { return load('https://www.gstatic.com/firebasejs/' + version + '/firebase-auth-compat.js'); })
      .then(function () {
        firebase.initializeApp({ apiKey: apiKey, projectId: project, authDomain: project + '.firebaseapp.com' });
        return firebase.auth().setPersistence(firebase.auth.Auth.Persistence.NONE);
      })
      .then(function () { loaded = true; });
  }

  function start(apiKey, project) {
    ready = ready || setUp(apiKey, project).catch(function (e) {
      ready = null;
      throw e;
    });
    return ready;
  }

  // Downloads Firebase while the sign-in page is open, so the tap on
  // "Continue with Google" can open the window straight away. Browsers
  // block a window opened after waiting for a download, which made the
  // first tap do nothing.
  window.bankTrackGooglePrepare = function (apiKey, project) {
    start(apiKey, project).catch(function () {});
  };

  // Resolves to JSON text: {uid, email, idToken, refreshToken} or {error}.
  window.bankTrackGoogleSignIn = async function (apiKey, project) {
    try {
      // Only wait when Firebase isn't there yet: any wait before the popup
      // opens can make the browser block it.
      if (!loaded) await start(apiKey, project);
      var provider = new firebase.auth.GoogleAuthProvider();
      provider.setCustomParameters({ prompt: 'select_account' });
      var result = await firebase.auth().signInWithPopup(provider);
      var user = result.user;
      var out = {
        uid: user.uid,
        email: user.email || '',
        idToken: await user.getIdToken(),
        refreshToken: user.refreshToken,
      };
      await firebase.auth().signOut();
      return JSON.stringify(out);
    } catch (e) {
      return JSON.stringify({ error: (e && e.code) || String(e) });
    }
  };
})();
