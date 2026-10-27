/// Central catalogue of the Bilibili API endpoints used by the app.
///
/// Keeping every path in one place makes it easy to audit which upstream
/// interfaces the player depends on.
abstract final class BiliEndpoints {
  /// Main API host (`api.bilibili.com`).
  static const String apiBase = 'https://api.bilibili.com';

  /// Passport host used for web login (`passport.bilibili.com`).
  static const String passportBase = 'https://passport.bilibili.com';

  // --- Account / authentication -------------------------------------------
  static const String nav = '/x/web-interface/nav';
  static const String navStat = '/x/web-interface/nav/stat';
  static const String exitLogin = '/login/exit/v2';

  // --- QR code login ------------------------------------------------------
  static const String qrGenerate = '/x/passport-login/web/qrcode/generate';
  static const String qrPoll = '/x/passport-login/web/qrcode/poll';

  // --- Phone (SMS) login --------------------------------------------------
  /// Geetest challenge required before a verification code can be sent.
  static const String captcha = '/x/passport-login/captcha';
  static const String smsSend = '/x/passport-login/web/sms/send';
  static const String smsLogin = '/x/passport-login/web/login/sms';

  // --- Search -------------------------------------------------------------
  static const String searchType = '/x/web-interface/wbi/search/type';

  // --- Video --------------------------------------------------------------
  static const String videoView = '/x/web-interface/view';
  static const String videoPlayUrl = '/x/player/wbi/playurl';

  // --- Favourites ---------------------------------------------------------
  static const String favFolderCreated = '/x/v3/fav/folder/created/list-all';
  static const String favFolderAdd = '/x/v3/fav/folder/add';
  static const String favFolderEdit = '/x/v3/fav/folder/edit';
  static const String favFolderDel = '/x/v3/fav/folder/del';
  static const String favResourceList = '/x/v3/fav/resource/list';
  static const String favResourceDeal = '/x/v3/fav/resource/deal';
  static const String favResourceBatchDel = '/x/v3/fav/resource/batch-del';

  // --- History ------------------------------------------------------------
  static const String historyCursor = '/x/web-interface/history/cursor';
  static const String historyReport = '/x/v2/history/report';
  static const String historyDelete = '/x/v2/history/delete';
  static const String historyClear = '/x/v2/history/clear';

  // --- Device identity ----------------------------------------------------
  static const String fingerSpi = '/x/frontend/finger/spi';
}
