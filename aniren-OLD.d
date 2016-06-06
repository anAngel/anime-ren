#!/usr/bin/env rdmd

/* aniren.d - aniren
 * Created by Rusty Shackleford on 2013/05/09
 * Copyright (c) 2013, Rusty Shackleford
 * All rights reserved. */

import std.stdio,
       std.socket,
       std.array,
       std.conv,
       std.getopt,
       md4.digest.md4,
       core.sync.mutex,
       core.thread;

import std.algorithm: filter;
import std.datetime:  StopWatch, SysTime, Clock;
import std.file:      dirEntries, SpanMode, isFile, exists, rename, FileException;
import std.path:      baseName, dirName, extension, expandTilde, stripExtension;
import std.regex:     regex, match, replace;
import std.string:    toLower, toUpper, format;
import std.math:      abs;

static {
  CONFIG conf;
  StopWatch sw;
  Socket sock;
  SysTime[] queries;
  bool dryrun = false;
  uint MAX_LEN = 255;

  const {
    string[] VID_EXTS = [ ".mkv", ".avi", ".mp4", ".mov", ".mpeg", ".mpg", ".rm", ".rmvb", ".ts", ".wmv" ];
    int ED2K_BLOCK = 9728000;

    string[] sys_chars   = [ r"\`", r"\:", r"\?", r"\/" ];
    int[] quote_replace  = [ 11, 14, 15 ]; // Entries that may contain single quotes
    string[] format_hash = [
      "%fid", "%aid", "%eid", "%gid", "",     "%ed2", "%md5", "%sha",
      "%crc", "%qua", "%src", "%aud", "%vid", "%res", "%dub", "%sub",
      "%eps", "%yea", "%typ", "%ann", "%kan", "%eng", "%enr", "%epn",
      "%epr", "%epk", "%grp", "%ver", "%inv", "%cen" ];
    int[][] fallbacks_series = [
      [ 20, 21 ],  // for %ann
      [ 19, 21 ],  // for %kan
      [ 19, 20 ]]; // for %eng
    int[][] fallbacks_episode = [
      [ 24, 25 ],  // for %eng
      [ 25, 23 ],  // for %ann
      [ 24, 23 ]]; // for %kan
  }
}

enum AM : long {
  /* Byte #1 */
  EPISODE_TOTAL           = 0x80000000,
  EPISODE_LAST            = 0x40000000,
  ANIME_YEAR              = 0x20000000,
  ANIME_TYPE              = 0x10000000,
  ANIME_RELATED           = 0x08000000,
  ANIME_RELATED_TYPE      = 0x04000000,
  ANIME_CATAGORY          = 0x02000000,
  // RESERVED             = 0x01000000,
  /* Byte #2 */
  ANIME_NAME_ROMAJI       = 0x00800000,
  ANIME_NAME_KANJI        = 0x00400000,
  ANIME_NAME_ENGLISH      = 0x00200000,
  ANIME_NAME_OTHER        = 0x00100000,
  ANIME_NAME_SHORT        = 0x00080000,
  ANIME_SYNONYMS          = 0x00040000,
  // RETIRED              = 0x00020000,
  // RETIRED              = 0x00010000,
  /* Byte #3 */
  EPISODE_NUMBER          = 0x00008000,
  EPISODE_NAME_ENGLISH    = 0x00004000,
  EPISODE_NAME_ROMAJI     = 0x00002000,
  EPISODE_NAME_KANJI      = 0x00001000,
  EPISODE_RATING          = 0x00000800,
  EPISODE_VOTECOUNT       = 0x00000400,
  // UNUSED               = 0x00000200,
  // UNUSED               = 0x00000100,
  /* Byte #4 */
  GROUP_NAME              = 0x00000080,
  GROUP_NAME_SHORT        = 0x00000040,
  // UNUSED               = 0x00000020,
  // UNUSED               = 0x00000010,
  // UNUSED               = 0x00000008,
  // UNUSED               = 0x00000004,
  // UNUSED               = 0x00000002,
  AID_UPDATE              = 0x00000001
}

enum FM : long {
  /* Byte #1 */
  // UNUSED               = 0x80000000,
  AID                     = 0x40000000,
  EID                     = 0x20000000,
  GID                     = 0x10000000,
  LID                     = 0x08000000,
  OTHER_EPS               = 0x04000000,
  // UNUSED               = 0x02000000,
  STATUS                  = 0x01000000,
  /* Byte #2 */
  SIZE                    = 0x00800000,
  ED2K                    = 0x00400000,
  MD5                     = 0x00200000,
  SHA1                    = 0x00100000,
  CRC32                   = 0x00080000,
  // UNUSED               = 0x00040000,
  // UNUSED               = 0x00020000,
  // UNUSED               = 0x00010000,
  /* Byte #3 */
  QUALITY                 = 0x00008000,
  SOURCE                  = 0x00004000,
  CODEC_AUDIO             = 0x00002000,
  BITRATE_AUDIO           = 0x00001000,
  CODEC_VIDEO             = 0x00000800,
  BITRATE_VIDEO           = 0x00000400,
  RESOLUTION              = 0x00000200,
  FILETYPE                = 0x00000100,
  /* Byte #4 */
  DUB_LANG                = 0x00000080,
  SUB_LANG                = 0x00000040,
  LENGTH                  = 0x00000020,
  DESCRIPTION             = 0x00000010,
  AIR_DATE                = 0x00000008,
  // UNUSED               = 0x00000004,
  // UNUSED               = 0x00000002,
  FILENAME                = 0x00000001
}

enum STATUS_CODES : int {
  CRCOK   = 0x01,
  CRCERR  = 0x02,
  ISV2    = 0x04,
  ISV3    = 0x08,
  ISV4    = 0x10,
  ISV5    = 0x20,
  UNCEN   = 0x40,
  CEN     = 0x80
}

enum RET_CODES : int {
  LOGIN_ACCEPTED              = 200,
  LOGIN_ACCEPTED_NEW_VERSION  = 201,
  MYLIST_ENTRY_ADDED          = 210,
  FILE                        = 220,
  FILE_ALREADY_IN_MYLIST      = 310,
  MYLIST_ENTRY_EDITED         = 311
}

struct API_RESP {
  int    code;
  string msg;
}

struct ED2K_RET {
  string hash, fname;
  ulong  len;
}

class CONFIG {
  int[string] dict;
  string[] vals;
  int conf_index = 0;

  public:
  this (const string loc) {
    // Add default formats
    add("format", "%enr. %ann - %epn (%typ, %src) [%crc] - %grp");
    add("movformat", "%eng (%src, %yea) [%crc] - %grp");
    add("ovaformat", "%enr. %ann - %epn (%typ, %src) [%crc] - %grp");

    if (loc.exists) {
      foreach (line; File(loc).byLine()) {
        if (line.empty || line[0] == '#')
          continue;

        auto l_split = split(line, "=");
        if (l_split.length != 2) {
          writefln("! ERROR: Invalid line in conf!\n\"%s\"", line);
          return;
        }

        add(to!string(l_split[0]), to!string(join(l_split[1..$], "=")));
      }
    } else {
      writefln("! ERROR: Failed to load config, \"%s\"", loc);
      core.stdc.stdlib.exit(-1);
    }

    // Make fmask and amask strings
    long acode = AM.ANIME_NAME_ROMAJI | AM.ANIME_NAME_KANJI |
      AM.ANIME_NAME_ENGLISH | AM.EPISODE_NAME_ENGLISH |
      AM.EPISODE_NAME_KANJI | AM.EPISODE_NAME_ROMAJI |
      AM.EPISODE_NUMBER | AM.GROUP_NAME_SHORT |
      AM.EPISODE_TOTAL | AM.ANIME_TYPE | AM.ANIME_YEAR;
    add("amask", format("%08X", acode));
    long fcode = FM.ED2K | FM.MD5 | FM.SHA1 |
      FM.CRC32 | FM.DUB_LANG | FM.SUB_LANG |
      FM.CODEC_VIDEO | FM.CODEC_AUDIO | FM.QUALITY |
      FM.SOURCE | FM.RESOLUTION | FM.STATUS |
      FM.AID | FM.EID | FM.GID;
    add("fmask", format("%08X", fcode));
  }

  void add (string key, string val) {
    if ((key in dict) !is null) {
      vals[dict[key]] = val;
    } else {
      vals ~= val;
      dict[key] = conf_index;
      conf_index++;
    }
  }

  string get (const string key) {
    return ((key in dict) !is null) ? vals[dict[key]] : "";
  }
}

int get_wait () {
  // Filter out queries older than 60 seconds
  queries = array(filter!(a => Clock.currTime().second - a.second < 60)(queries));

  // Return wait time based on #queries in last minute
  size_t total_queries = queries.length;
  if (total_queries == 0)
    return 0;
  else if (total_queries >= 1 && total_queries <= 10)
    return 2;
  else if (total_queries >= 11 && total_queries <= 15)
    return 3;
  else
    return 4;
}

void query_wait () {
  int wait = to!int(sw.peek.seconds) - get_wait;
  if (wait < 0 && sw.running) {
    Thread.sleep(dur!("seconds")(std.math.abs(wait)));
    sw.reset;
    sw.stop;
  }
}

ED2K_RET ed2k (const string loc) {
  ubyte[] hex  = [];
  ulong   size = 0;

  // Get MD4 hash of each 9500kb and concatenate the arrays
  writefln("~ Hashing \"%s\"", baseName(loc));
  foreach (ubyte[] buf; chunks(File(loc), ED2K_BLOCK)) {
    hex   = hex ~ md4Of(buf);
    size += buf.length;
  }

  // If less than one chunk, return the only hash, otherwise hash the string
  ED2K_RET ret = { toHexString(size <= ED2K_BLOCK ? hex : md4Of(hex)), loc, size };
  return ret;
}

API_RESP execute (Char, A...)(in Char[] fmt, A args) {
  auto app = appender!string();
  std.format.formattedWrite(app, fmt, args);
  string cmd = app.data;

  writefln("> %s", (match(cmd, regex("^AUTH")) ?
         replace(cmd, regex(conf.get("pass"), "g"), "*****") :
         replace(cmd, regex("\n", "g"), " - ")));
  query_wait;

  ushort tries = 3;
  string ret   = null;
  while (tries > 0) {
    sock.send(cast(byte[])cmd);
    ubyte[] recv_buf = new ubyte[](1024);
    auto read = sock.receive(recv_buf);
    if (read == Socket.ERROR) {
      tries--;
      writefln("! ERROR: Connection error! %d tries left...", tries);
      query_wait;
    } else if (read == 0) {
      write("! ERROR: ");
      try {
        writefln("Connection from %s closed.", sock.remoteAddress().toString());
      } catch (SocketException) {
        writeln("Connection closed.");
      }
      break;
    } else {
      ret = cast(string)(recv_buf[0..read - 1]);
      break;
    }
  }
  if (ret == null) {
    sock.close();
    core.stdc.stdlib.exit(-1);
  }

  auto ret_split = split(ret, " ");
  API_RESP resp = { to!int(ret_split[0]), join(ret_split[1..$], " ") };
  if (resp.code == RET_CODES.MYLIST_ENTRY_EDITED)
    ret = ret[0..$ - 2];
  writefln("< %s", ret);

  queries ~= Clock.currTime();
  sw.start();
  return resp;
}

// Send AUTH command and assign the session key
bool AUTH () {
  API_RESP auth_ret = execute("AUTH user=%s&pass=%s&protover=3&client=aniren&clientver=2&enc=UTF8", conf.get("user"), conf.get("pass"));
  if (auth_ret.code == RET_CODES.LOGIN_ACCEPTED || auth_ret.code == RET_CODES.LOGIN_ACCEPTED_NEW_VERSION) {
    conf.add("session", split(auth_ret.msg, " ")[0]);
    return true;
  } else {
    writeln("! ERROR: Failed to to authentice session");
    return false;
  }
}

// Send FILE command and return new file name based on format
int FILE (const ref ED2K_RET hash) {
  bool  too_long    = false;
  string fname_base = baseName(hash.fname);

  writefln("~ Processing \"%s\"", fname_base);
  API_RESP f_ret = execute("FILE size=%d&ed2k=%s&fmask=%s&amask=%s&s=%s", hash.len, hash.hash, conf.get("fmask"), conf.get("amask"), conf.get("session"));

  if (f_ret.code == RET_CODES.FILE) {
    string[] ret_parts = split(f_ret.msg, "|");
    auto m = match(ret_parts[0], regex(r"(?P<cmd>\w+)\n(?P<fid>\d+)"));
    if (m && m.captures["cmd"] == "FILE") {
      int fid = to!int(m.captures["fid"]);

      // Parse status return
      int status = to!int(ret_parts[4]);
      string ver = "",
             cen = "",
             crc = "CRCUC";

      if (status & STATUS_CODES.ISV2)
        ver = "v2";
      else if (status & STATUS_CODES.ISV3)
        ver = "v3";
      else if (status & STATUS_CODES.ISV4)
        ver = "v4";
      else if (status & STATUS_CODES.ISV5)
        ver = "v5";

      if (status & STATUS_CODES.CEN)
        cen = "CEN";
      else if (status & STATUS_CODES.UNCEN)
        cen = "UNCEN";

      if (status & STATUS_CODES.CRCOK)
        crc = "CRCOK";
      else if (status & STATUS_CODES.CRCERR)
        crc = "CRCERR";

      // Append status parts
      ret_parts ~= ver;
      ret_parts ~= cen;
      ret_parts ~= crc;

      // Replace single quotes with commas
      foreach (int cur; quote_replace)
        ret_parts[cur] = replace(ret_parts[cur], regex(r"'", "g"), ",");

      // Fill in null series names
      for (int i = 19; i <= 22; ++i) {
        if (ret_parts[i] == null) {
          foreach (int j; fallbacks_series[i - 19]) {
            if (ret_parts[j] != null) {
              ret_parts[i]  = ret_parts[j];
              break;
            }}}}

      // Fill in null episodes names
      if (ret_parts[18] != "Movie") { // Except for movies
        for (int i = 23; i <= 25; ++i) {
          if (ret_parts[i] == null) {
            foreach (int j; fallbacks_episode[i - 23]) {
              if (ret_parts[j] != null) {
                ret_parts[i]  = ret_parts[j];
                break;
              }}}}}

START_OVER:
      // Get format from config
      string format = "";
      switch (ret_parts[18]) {
        case "OVA":
          format = conf.get("ovaformat");
          break;
        case "Movie":
          format = conf.get("movformat");
          break;
        default:
          format = conf.get("format");
      }

      if (too_long)
        ret_parts[23..25] = "Episode " ~ ret_parts[22];

      // Put hashes into uppercase
      foreach (ref string cur; ret_parts[5..9])
        cur = cur.toUpper;

      // Parse the year
      string[] yea_parts = split(ret_parts[17], "-");
      if (yea_parts.length == 2 && (yea_parts[0] == yea_parts[1]))
        ret_parts[17] = yea_parts[0];

      for (int i = 0; i < format_hash.length; ++i)
        if (!format_hash[i].empty)
          format = replace(format, regex(format_hash[i], "g"), ret_parts[i]);

      // Remove invalid system characters to prevent renaming failure
      foreach (string cur; sys_chars)
        format = replace(format, regex(cur, "g"), "");
      format = replace(format, regex(r" /", "g"), ",");

      string final_format  = dirName(hash.fname) ~ "/" ~ format;
      string orig_ext      = extension(hash.fname);
      string subtitles_old = stripExtension(hash.fname) ~ ".ass";
      string subtitles_new = final_format ~ ".ass";
      string final_out     = final_format ~ orig_ext;

      if (final_out.length > MAX_LEN) {
        if (ret_parts[18] == "Movie")
          return 0;
        else {
          too_long = true;
          goto START_OVER;
        }
      } else {
        if (exists(subtitles_old) && !exists(subtitles_new)) {
          try {
            if (!dryrun)
              rename(subtitles_old, subtitles_new);
            writefln("~ %s => %s", subtitles_old, subtitles_new);
          } catch (FileException) {
            writefln("! ERROR: Rename failed: %s => %s", subtitles_old, subtitles_new);
            return 0;
          }
        }
        if (!exists(final_out)) {
          try {
            if (!dryrun)
              rename(hash.fname, final_out);
            writefln("~ %s => %s", fname_base, format ~ orig_ext);
            return (dryrun ? 0 : fid);
          } catch (FileException) {
            writefln("! ERROR: Rename failed: %s => %s", fname_base, format ~ orig_ext);
            return 0;
          }
        } else {
          writefln("! ERROR: \"%s\" already exists!", baseName(final_out));
          return 0;
        }
      }
    } else
      return 0;
  } else
    return 0;
}

void MYLISTADD (const int fid) {
  if (conf.get("mladd").empty)
    return; // Don't add

  string exec_cmd = format("MYLISTADD fid=%d", fid);

  string mlstate = conf.get("mlstate");
  int mlstate_i  = -1;
  if (!mlstate.empty) {
    mlstate_i = to!int(mlstate);
    if (mlstate_i >= 0 && mlstate_i <= 3)
      exec_cmd ~= format("&state=%d", mlstate_i);
  }

  string mlviewed = conf.get("mlviewed");
  int mlviewed_i  = -1;
  if (!mlviewed.empty) {
    mlviewed_i = to!int(mlviewed);
    if (mlviewed_i == 0 || mlviewed_i == 1)
      exec_cmd ~= format("&viewed=%d", mlviewed_i);
  }

  API_RESP ml = execute("%s&s=%s", exec_cmd, conf.get("session"));
  if (ml.code == RET_CODES.FILE_ALREADY_IN_MYLIST && !conf.get("mledit").empty) {
    string[] ml_parts = split(split(ml.msg, "\n")[1], "|");

    // Check if MyList values are different
    bool ml_edit = false;
    if (mlstate_i != -1)
      if (mlstate_i != to!int(ml_parts[6]))
        ml_edit = true;

    if (mlviewed_i != -1)
      if (mlviewed_i == 1 && to!int(ml_parts[7]) == 0)
        ml_edit = true;

    // Only send if values are different
    if (ml_edit)
      execute("%s&edit=1&s=%s", exec_cmd, conf.get("session"));
  }
}

void main (string[] args) {
  string config_path = expandTilde("~/.aniren.conf");
  if (!exists(config_path))
    config_path = ".aniren.conf";

  bool recursive = false, write_help = false;
  int  threads   = 1;
  getopt(args, std.getopt.config.passThrough,
      "config|c",    &config_path,
      "recursive|r", &recursive,
      "dry-run",     &dryrun,
      "help|h",      &write_help,
      "threads|t",   &threads);

  if (write_help) {
    writeln("./aniren [options] [paths]");
    writeln("\nOptions:");
    writeln("\t--config|-c $ => Define config path [default: ./.aniren.conf]");
    writeln("\t--recursive|-r => Search folders recursivly");
    writeln("\t--dry-run => Run normally, but don't rename or edit MyList");
    writeln("\t--threads|-t $ => Number of threads to run for hashing");
    writeln("\t--help|-h => Print this message");
    writeln("\nPaths:");
    writeln("  Pass file names or glob searches, like *.* or *.mkv [default: *.*]");
    return;
  }

  // Try and load config
  conf = new CONFIG(config_path);

  // Go through remaining args, use as glob matches
  // If there are no arguments, then just search for all
  SpanMode span = (recursive ? SpanMode.depth : SpanMode.shallow);
  string[] input_files_args = args[1..$];
  string[] job_list;
  if (input_files_args.empty) {
    foreach (string file; dirEntries(".", span))
      job_list ~= file;
  } else {
    version (Windows) {
      foreach (string glob; input_files_args)
        foreach (string file; dirEntries(".", glob, span))
          job_list ~= file;
    } else
      job_list = input_files_args;
  }

  // Filter out the invalid video files
  bool valid_vid(const string path) {
    if (!path.exists || !path.isFile)
      return false;

    string tmp_ext = extension(path).toLower();
    foreach (string ext; VID_EXTS)
      if (tmp_ext == ext)
        return true;
    return false;
  }
  job_list = array(filter!(a => valid_vid(a))(job_list));

  if (job_list.empty) {
    writeln("No entries in job list! Nothing to do!");
    return;
  }

  // Check No. threads
  if (threads <= 0)
    threads = 1;
  if (threads > job_list.length)
    threads = cast(int)job_list.length;

  // Write out job list
  writeln("Job list:");
  foreach (string job; job_list)
    writefln("  => %s", job);
  writeln;

  ED2K_RET[] hash_list;
  Mutex ed2k_mutex = new Mutex;
  void ed2k_thread_func () {
    while (!job_list.empty) {
      string cur_path;
      synchronized (ed2k_mutex) {
        cur_path = job_list.front;
        job_list.popFront();
      }

      ED2K_RET cur_ret = ed2k(cur_path);
      synchronized (ed2k_mutex)
        hash_list ~= cur_ret;
    }
  }

  // Hash files along side the UDP commands
  Thread[] ed2k_threads = new Thread[threads];
  for (int i = 0; i < threads; ++i) {
    ed2k_threads[i] = new Thread(&ed2k_thread_func);
    ed2k_threads[i].start;
  }

  bool thread_still_running() {
    foreach (Thread t; ed2k_threads)
      if (t.isRunning)
        return true;
    return false;
  }

  try {
    auto addr = new InternetAddress(getAddress(conf.get("serv"))[0].toAddrString(),
                                     to!ushort(conf.get("port")));
    sock = new UdpSocket;
    sock.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!("seconds")(10));
    sock.bind(new InternetAddress(to!ushort(conf.get("port"))));
    sock.connect(addr);

    scope (exit) {
      execute("LOGOUT s=%s", conf.get("session"));
      sock.close();

      if (thread_still_running())
        core.stdc.stdlib.exit(-1);
    }

    if (!AUTH)
      core.stdc.stdlib.exit(-1);

    // While there is still work to be done
    while (!hash_list.empty || (!job_list.empty || thread_still_running())) {
      if (!hash_list.empty) {
        int fid = FILE(hash_list.front);
        if (fid)
          MYLISTADD(fid);
        synchronized (ed2k_mutex)
          hash_list.popFront;
      }
    }
  }
  catch (SocketException e) {
    writefln("! ERROR: Failed to lookup: %s", e.msg);
    core.stdc.stdlib.exit(-1);
  }
}

