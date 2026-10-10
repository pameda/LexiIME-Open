using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.Encodings.Web;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Security.Cryptography;

// Only the two explicit payload types below cross the chosen folder boundary.
// No network/cloud SDKs; the user's existing folder provider does the transport.
internal sealed class DictionarySync {
    internal sealed record Conflict(string Code,string? Local,string[] Remote);
    internal sealed record Result(int Dictionaries,int Phrases,Conflict[] Conflicts);
    sealed record DictionaryBlob(string Hash,byte[] Bytes,string? LocalPath);
    const int MiB=1024*1024,MaxDictionaries=128,MaxSnapshots=128;
    static readonly UTF8Encoding Utf8=new(false,true);
    readonly string root,data,config;
    readonly HashSet<string> ignoredDictionaries=new(StringComparer.Ordinal);
    readonly HashSet<string> ignoredPhraseCodes=new(StringComparer.Ordinal);
    readonly HashSet<string> ignoredVariants=new(StringComparer.Ordinal);
    readonly HashSet<string> knownDictionaries=new(StringComparer.Ordinal);
    readonly HashSet<string> knownPhraseCodes=new(StringComparer.Ordinal);
    internal bool Enabled {get;private set;}
    internal string Folder {get;private set;}="";
    internal string Provider {get;private set;}="other";
    internal string DeviceID {get;private set;}=Guid.NewGuid().ToString("D");
    string LocalDictionaries=>Path.Combine(root,"Dictionaries");
    string LocalPhrases=>Path.Combine(root,"phrases.tsv");
    internal DictionarySync(string root,string data){
        this.root=Path.GetFullPath(root);this.data=Path.GetFullPath(data);config=Path.Combine(root,"settings.ini");
        var ini=ReadIni(config);
        Enabled=ini.GetValueOrDefault("sync_enabled")=="1";
        Folder=ini.GetValueOrDefault("sync_folder","");
        string provider=ini.GetValueOrDefault("sync_provider","other");
        Provider=provider=="icloud"||provider=="synology"?provider:"other";
        string id=ini.GetValueOrDefault("sync_device_id","");
        if(ValidID(id))DeviceID=id;
        else if(Enabled)Enabled=false; // Never publish over another device's identity.
        ReadSet(ini,"sync_ignored_dictionaries",ignoredDictionaries,ValidHash);
        ReadSet(ini,"sync_ignored_phrase_codes",ignoredPhraseCodes,ValidCode);
        ReadSet(ini,"sync_ignored_variants",ignoredVariants,ValidHash);
        ReadSet(ini,"sync_known_dictionaries",knownDictionaries,ValidHash);
        ReadSet(ini,"sync_known_phrase_codes",knownPhraseCodes,ValidCode);
    }
    static bool ValidID(string s)=>Guid.TryParseExact(s,"D",out var id)&&id.ToString("D")==s;
    static bool ValidHash(string s)=>s.Length==64&&s.All(c=>(c>='0'&&c<='9')||(c>='a'&&c<='f'));
    static bool ValidCode(string s)=>s.Length>=1&&s.Length<=32&&s.All(c=>c>='a'&&c<='z');
    static string Hash(byte[] bytes)=>Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    static string Variant(string code,string text)=>Hash(Utf8.GetBytes(code+"\t"+text));
    static void ReadSet(Dictionary<string,string> ini,string key,HashSet<string> set,Func<string,bool> valid){
        if(!ini.TryGetValue(key,out var value)||value.Length==0)return;
        foreach(string item in value.Split(',')){
            if(!valid(item))throw new IOException("同步抑制记录无效，未执行同步。");
            set.Add(item);
            if(set.Count>32768)throw new IOException("同步抑制记录过大。");
        }
    }
    static Dictionary<string,string> ReadIni(string path){
        var result=new Dictionary<string,string>(StringComparer.Ordinal);
        GuardPath(path);if(!File.Exists(path))return result;
        foreach(string line in Utf8.GetString(ReadBounded(path,4*MiB)).Split('\n')){
            string clean=line.TrimEnd('\r');int eq=clean.IndexOf('=');
            if(eq>0)result[clean[..eq]]=clean[(eq+1)..];
        }
        return result;
    }
    // Shared by Settings: merge only owned fields, retain unknown fields/comments,
    // and serialize read/replace so two settings processes cannot lose each other's fields.
    internal static void MergeIni(string path,IReadOnlyDictionary<string,string> values){
        foreach(var pair in values)if(pair.Value.IndexOfAny(new[]{'\r','\n','\0'})>=0)throw new IOException("设置值不能包含换行或空字符。");
        GuardPath(path);string lockPath=path+".lock";GuardPath(lockPath);
        using var gate=new FileStream(lockPath,FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);
        var lines=File.Exists(path)?Utf8.GetString(ReadBounded(path,4*MiB)).Split('\n').ToList():new List<string>();
        if(lines.Count>0&&lines[^1].Length==0)lines.RemoveAt(lines.Count-1);
        var found=new HashSet<string>(StringComparer.Ordinal);
        for(int i=0;i<lines.Count;i++){
            string line=lines[i].TrimEnd('\r');int eq=line.IndexOf('=');
            if(eq<0)continue;string name=line[..eq];
            if(values.TryGetValue(name,out string? value)){lines[i]=name+"="+value;found.Add(name);}
        }
        foreach(var pair in values){
            if(!found.Contains(pair.Key))lines.Add(pair.Key+"="+pair.Value);
        }
        byte[] merged=Utf8.GetBytes(string.Join("\n",lines)+"\n");
        if(merged.Length>4*MiB)throw new IOException("设置与同步抑制记录超过 4 MiB，未覆盖原文件。");
        Atomic(path,merged,true);
    }
    internal void Configure(bool enabled,string folder,string provider){
        if(provider!="icloud"&&provider!="synology"&&provider!="other")throw new IOException("请选择同步文件夹类型。");
        if(folder.Length>0)ValidateFolder(folder);
        if(enabled&&folder.Length==0)throw new IOException("请先选择已在本机存在的同步文件夹。");
        MergeIni(config,new Dictionary<string,string>{["sync_enabled"]=enabled?"1":"0",["sync_folder"]=folder,["sync_provider"]=provider,["sync_device_id"]=DeviceID});
        Enabled=enabled;Folder=folder;Provider=provider;
    }
    internal void ValidateFolder(string folder){
        string full=Path.GetFullPath(folder);GuardPath(full);
        if(!Directory.Exists(full))throw new IOException("同步文件夹必须已存在于本机。");
        if(Within(full,root))throw new IOException("同步文件夹不能位于本机 LexiIME-Open 数据目录内。");
        // The payload subtree may not reach back into local data through an ancestor.
        if(Within(root,Path.Combine(full,"LexiIME-Open-Sync")))throw new IOException("同步数据目录不能包含本机 LexiIME-Open 数据目录。");
    }
    static bool Within(string path,string parent){
        string p=Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
        string r=Path.TrimEndingDirectorySeparator(Path.GetFullPath(parent));
        return p.Equals(r,StringComparison.OrdinalIgnoreCase)||p.StartsWith(r+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase);
    }
    // Check every existing path component, including ancestors and dangling links.
    // Windows junctions/cloud placeholders with ReparsePoint are deliberately refused.
    internal static void GuardPath(string path){
        string full=Path.GetFullPath(path),anchor=Path.GetPathRoot(full)??throw new IOException("路径无效。");
        string current=anchor;Check(current);
        foreach(string part in full[anchor.Length..].Split(new[]{Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar},StringSplitOptions.RemoveEmptyEntries)){
            current=Path.Combine(current,part);Check(current);
        }
        static void Check(string p){
            try{if((File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)throw new IOException("同步路径不能包含符号链接、联接或重解析点。");}
            catch(FileNotFoundException){}catch(DirectoryNotFoundException){}
        }
    }
    static byte[] ReadBounded(string path,int max){
        GuardPath(path);
        using var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read);
        if(stream.Length>max)throw new IOException("同步文件超过大小限制。");
        using var bytes=new MemoryStream();var block=new byte[8192];int n;
        while((n=stream.Read(block,0,Math.Min(block.Length,max+1-(int)bytes.Length)))>0){
            bytes.Write(block,0,n);if(bytes.Length>max)throw new IOException("同步文件超过大小限制。");
        }
        GuardPath(path);return bytes.ToArray();
    }
    static void FilePath(string path){GuardPath(path);if(Directory.Exists(path))throw new IOException("文件目标不能是目录。");}
    static void Atomic(string path,byte[] bytes,bool replace){
        FilePath(path);string staged=path+"."+Guid.NewGuid().ToString("N")+".tmp";
        try{
            GuardPath(staged);
            using(var stream=new FileStream(staged,FileMode.CreateNew,FileAccess.Write,FileShare.None)){stream.Write(bytes);stream.Flush(true);}
            GuardPath(path);GuardPath(staged);
            if(replace&&File.Exists(path))File.Replace(staged,path,null);
            else File.Move(staged,path); // add-only: never overwrite an existing dictionary.
        }finally{GuardPath(staged);if(File.Exists(staged))File.Delete(staged);}
    }
    static void EnsureDirectory(string path){GuardPath(path);Directory.CreateDirectory(path);GuardPath(path);}
    static string[] Files(string directory,string pattern,int limit){
        GuardPath(directory);if(!Directory.Exists(directory))return Array.Empty<string>();
        var paths=Directory.EnumerateFiles(directory,pattern,SearchOption.TopDirectoryOnly).Take(limit+1).OrderBy(p=>p,StringComparer.Ordinal).ToArray();
        if(paths.Length>limit)throw new IOException("同步文件数量超过限制。");
        foreach(string path in paths)GuardPath(path);return paths;
    }
    static Dictionary<string,string> ValidatePhrases(IEnumerable<KeyValuePair<string,string>> rows){
        var result=new Dictionary<string,string>(StringComparer.Ordinal);
        foreach(var row in rows){
            if(result.Count>=1000||!ValidCode(row.Key)||!result.TryAdd(row.Key,row.Value))throw new IOException("常用语最多 1,000 个唯一的小写字母触发码，每码 1–32 字符。");
            int size=Utf8.GetByteCount(row.Value);
            if(size<1||size>512||row.Value.Any(char.IsControl))throw new IOException("常用语正文必须为 1–512 个 UTF-8 字节，不能含控制字符。");
        }
        if(PhraseTSV(result).Length>MiB)throw new IOException("常用语超过 1 MiB。");
        return result;
    }
    static byte[] PhraseTSV(Dictionary<string,string> phrases)=>Utf8.GetBytes(string.Concat(phrases.OrderBy(p=>p.Key,StringComparer.Ordinal).Select(p=>p.Key+"\t"+p.Value+"\n")));
    static Dictionary<string,string> ReadLocalPhrases(string path){
        GuardPath(path);if(!File.Exists(path))return new(StringComparer.Ordinal);
        string text=Utf8.GetString(ReadBounded(path,MiB));var rows=new List<KeyValuePair<string,string>>();
        var lines=text.Split('\n');for(int i=0;i<lines.Length;i++){
            if(i==lines.Length-1&&lines[i].Length==0)break;
            string line=i<lines.Length-1&&lines[i].EndsWith('\r')?lines[i][..^1]:lines[i];string[] fields=line.Split('\t');
            if(fields.Length!=2)throw new IOException("本机常用语文件格式无效。");
            rows.Add(new(fields[0],fields[1]));
        }
        return ValidatePhrases(rows);
    }
    static void Fields(JsonElement element,params string[] names){
        if(element.ValueKind!=JsonValueKind.Object)throw new IOException("常用语快照格式无效。");
        var seen=new HashSet<string>(StringComparer.Ordinal);
        foreach(var property in element.EnumerateObject())if(!names.Contains(property.Name,StringComparer.Ordinal)||!seen.Add(property.Name))throw new IOException("常用语快照字段无效或重复。");
        if(seen.Count!=names.Length)throw new IOException("常用语快照字段缺失。");
    }
    static Dictionary<string,string> ReadSnapshot(byte[] bytes){
        if(bytes.Length>MiB)throw new IOException("常用语快照超过 1 MiB。");Utf8.GetString(bytes); // Reject invalid UTF-8, including escaped surrogate errors below.
        using var json=JsonDocument.Parse(bytes,new JsonDocumentOptions{MaxDepth=8});var doc=json.RootElement;
        Fields(doc,"version","phrases");
        if(doc.GetProperty("version").ValueKind!=JsonValueKind.Number||!doc.GetProperty("version").TryGetInt32(out int version)||version!=1||doc.GetProperty("phrases").ValueKind!=JsonValueKind.Array)throw new IOException("常用语快照版本或格式不受支持。");
        var rows=new List<KeyValuePair<string,string>>();
        foreach(var row in doc.GetProperty("phrases").EnumerateArray()){
            if(rows.Count>=1000)throw new IOException("常用语快照超过 1,000 条。");
            Fields(row,"code","text");
            if(row.GetProperty("code").ValueKind!=JsonValueKind.String||row.GetProperty("text").ValueKind!=JsonValueKind.String)throw new IOException("常用语快照字段必须为字符串。");
            rows.Add(new(row.GetProperty("code").GetString()!,row.GetProperty("text").GetString()!));
        }
        return ValidatePhrases(rows);
    }
    static byte[] Snapshot(Dictionary<string,string> phrases){
        byte[] bytes=JsonSerializer.SerializeToUtf8Bytes(new{version=1,phrases=phrases.OrderBy(p=>p.Key,StringComparer.Ordinal).Select(p=>new{code=p.Key,text=p.Value}).ToArray()},new JsonSerializerOptions{Encoder=JavaScriptEncoder.UnsafeRelaxedJsonEscaping});
        if(bytes.Length>MiB)throw new IOException("常用语 JSON 快照超过 1 MiB。");return bytes;
    }
    List<DictionaryBlob> LocalBlobs(){
        var result=new List<DictionaryBlob>();long bytes=0;
        foreach(string path in Files(LocalDictionaries,"*.tsv",MaxDictionaries)){
            byte[] contents=ReadBounded(path,8*MiB);bytes+=contents.Length;
            if(bytes>64L*MiB)throw new IOException("本机自定义词库合计超过 64 MiB。");
            result.Add(new(Hash(contents),contents,path));
        }
        return result;
    }
    static List<DictionaryBlob> RemoteBlobs(string directory){
        var result=new List<DictionaryBlob>();long bytes=0;
        foreach(string path in Files(directory,"*.tsv",MaxDictionaries)){
            string hash=Path.GetFileNameWithoutExtension(path);
            if(!ValidHash(hash)||Path.GetFileName(path)!=hash+".tsv")throw new IOException("同步词库文件名必须为小写 SHA-256。");
            byte[] contents=ReadBounded(path,8*MiB);bytes+=contents.Length;
            if(bytes>64L*MiB||Hash(contents)!=hash)throw new IOException("同步词库大小或 SHA-256 校验失败。");
            result.Add(new(hash,contents,null));
        }
        return result;
    }
    void State(IEnumerable<string> hashes,IEnumerable<string> codes){
        var currentHashes=hashes.ToHashSet(StringComparer.Ordinal);var currentCodes=codes.ToHashSet(StringComparer.Ordinal);
        // Suppress deletions before reading any remote payload. Removal while sync
        // was off is detected against the last successful local inventory, too.
        ignoredDictionaries.UnionWith(knownDictionaries.Except(currentHashes));
        ignoredPhraseCodes.UnionWith(knownPhraseCodes.Except(currentCodes));
        PersistState(currentHashes,currentCodes);
    }
    void PersistState(HashSet<string> hashes,HashSet<string> codes){
        static string Join(HashSet<string> set){if(set.Count>32768)throw new IOException("同步抑制记录过大。");return string.Join(",",set.OrderBy(x=>x,StringComparer.Ordinal));}
        MergeIni(config,new Dictionary<string,string>{["sync_ignored_dictionaries"]=Join(ignoredDictionaries),["sync_ignored_phrase_codes"]=Join(ignoredPhraseCodes),["sync_ignored_variants"]=Join(ignoredVariants),["sync_known_dictionaries"]=Join(hashes),["sync_known_phrase_codes"]=Join(codes)});
        knownDictionaries.Clear();knownDictionaries.UnionWith(hashes);knownPhraseCodes.Clear();knownPhraseCodes.UnionWith(codes);
    }
    // Called only after an explicit local Save/Import, so a subsequent deletion
    // cannot vanish from the baseline before the first automatic timer tick.
    internal void RememberLocal(IEnumerable<string>? previousPhraseCodes=null){
        GuardPath(root);string lockPath=Path.Combine(root,"sync.lock");GuardPath(lockPath);
        using var gate=new FileStream(lockPath,FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);
        if(previousPhraseCodes!=null)knownPhraseCodes.UnionWith(previousPhraseCodes);
        State(LocalBlobs().Select(b=>b.Hash),ReadLocalPhrases(LocalPhrases).Keys);
    }
    internal Result Run(string? resolveCode=null,string? remoteText=null,bool keepLocal=false){
        if(!Enabled)throw new IOException("文件夹同步已关闭。");
        ValidateFolder(Folder);GuardPath(root);GuardPath(data);
        string lockPath=Path.Combine(root,"sync.lock");GuardPath(lockPath);
        using var gate=new FileStream(lockPath,FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);
        // Each sync uses immutable, bounded byte snapshots. Core validates those
        // same bytes instead of reopening provider files after validation.
        var local=LocalBlobs();var phrases=ReadLocalPhrases(LocalPhrases);
        bool phraseExisted=File.Exists(LocalPhrases);byte[] originalPhraseBytes=phraseExisted?ReadBounded(LocalPhrases,MiB):Array.Empty<byte>();
        State(local.Select(b=>b.Hash),phrases.Keys);
        string shared=Path.Combine(Path.GetFullPath(Folder),"LexiIME-Open-Sync"),dictDir=Path.Combine(shared,"dictionaries"),phraseDir=Path.Combine(shared,"phrases");
        GuardPath(shared);GuardPath(dictDir);GuardPath(phraseDir);
        var remote=RemoteBlobs(dictDir);var remotePhrases=new Dictionary<string,HashSet<string>>(StringComparer.Ordinal);
        byte[]? originalOwnSnapshot=null;
        string[] snapshots=Files(phraseDir,"*.json",MaxSnapshots);
        foreach(string path in snapshots){
            string id=Path.GetFileNameWithoutExtension(path);
            if(!ValidID(id)||Path.GetFileName(path)!=id+".json")throw new IOException("常用语快照文件名必须为小写 UUID。");
            byte[] original=ReadBounded(path,MiB);var snapshotPhrases=ReadSnapshot(original);
            if(id==DeviceID){originalOwnSnapshot=original;continue;} // Validate, but never pull our own previous snapshot.
            foreach(var row in snapshotPhrases){
                if(ignoredPhraseCodes.Contains(row.Key)||ignoredVariants.Contains(Variant(row.Key,row.Value)))continue;
                if(!remotePhrases.TryGetValue(row.Key,out var texts))remotePhrases[row.Key]=texts=new(StringComparer.Ordinal);
                texts.Add(row.Value);
            }
        }
        var localHashes=local.Select(b=>b.Hash).ToHashSet(StringComparer.Ordinal);
        var incoming=remote.Where(b=>!localHashes.Contains(b.Hash)&&!ignoredDictionaries.Contains(b.Hash)).ToList();
        var combined=local.Concat(incoming).ToList();
        if(combined.Count>MaxDictionaries||combined.Sum(b=>(long)b.Bytes.Length)>64L*MiB)throw new IOException("合并后的自定义词库超过 128 个或 64 MiB。");
        // Also bound the add-only shared directory before publishing any local file.
        var publishLocal=local.Where(b=>!ignoredDictionaries.Contains(b.Hash)).GroupBy(b=>b.Hash,StringComparer.Ordinal).Select(g=>g.First()).ToArray();
        var sharedBlobs=remote.Concat(publishLocal).GroupBy(b=>b.Hash,StringComparer.Ordinal).Select(g=>g.First()).ToArray();
        if(sharedBlobs.Length>MaxDictionaries||sharedBlobs.Sum(b=>(long)b.Bytes.Length)>64L*MiB)throw new IOException("共享词库目录已达到 128 个或 64 MiB 上限。");
        string ownSnapshot=Path.Combine(phraseDir,DeviceID+".json");FilePath(ownSnapshot);
        CheckOwnSnapshot(ownSnapshot,originalOwnSnapshot);
        if(originalOwnSnapshot==null&&snapshots.Length>=MaxSnapshots)throw new IOException("共享常用语快照已达到 128 个上限。");
        var nextIgnoredVariants=new HashSet<string>(ignoredVariants,StringComparer.Ordinal);
        var nextIgnoredCodes=new HashSet<string>(ignoredPhraseCodes,StringComparer.Ordinal);
        int added=0;var conflicts=new List<Conflict>();bool resolved=resolveCode==null;
        foreach(var row in remotePhrases.OrderBy(p=>p.Key,StringComparer.Ordinal)){
            phrases.TryGetValue(row.Key,out string? own);string[] choices=row.Value.OrderBy(t=>t,StringComparer.Ordinal).ToArray();
            bool conflict=choices.Length>1||(own!=null&&choices[0]!=own);
            if(conflict){
                if(row.Key==resolveCode){
                    if(keepLocal){foreach(string text in choices)nextIgnoredVariants.Add(Variant(row.Key,text));if(own==null)nextIgnoredCodes.Add(row.Key);}
                    else{
                        if(remoteText==null||!row.Value.Contains(remoteText))throw new IOException("远端版本已变化，请刷新冲突列表。");
                        foreach(string text in choices)nextIgnoredVariants.Add(Variant(row.Key,text));
                        nextIgnoredCodes.Remove(row.Key);phrases[row.Key]=remoteText;
                    }
                    resolved=true;
                }else conflicts.Add(new(row.Key,own,choices));
            }else if(own==null){phrases.Add(row.Key,choices[0]);added++;}
        }
        if(!resolved)throw new IOException("此冲突已变化，请重新同步后选择。");
        if(nextIgnoredVariants.Count>32768||nextIgnoredCodes.Count>32768)throw new IOException("同步抑制记录过大。");
        // ignoredVariants applies only to remote input; even an adopted/seen variant is published from local state.
        phrases=ValidatePhrases(phrases);byte[] phraseBytes=PhraseTSV(phrases),snapshot=Snapshot(phrases.Where(p=>!nextIgnoredCodes.Contains(p.Key)).ToDictionary(p=>p.Key,p=>p.Value,StringComparer.Ordinal));
        string stage=Path.Combine(root,"sync-stage-"+Guid.NewGuid().ToString("N"));EnsureDirectory(stage);
        try{
            var staged=new List<string>();for(int i=0;i<combined.Count;i++){string path=Path.Combine(stage,i+".tsv");Atomic(path,combined[i].Bytes,false);staged.Add(path);}
            string stagedPhrases=Path.Combine(stage,"phrases.tsv");Atomic(stagedPhrases,phraseBytes,false);
            ValidateCore(staged,stagedPhrases); // Includes builtin + local + incoming; no pull has occurred.
            EnsureDirectory(dictDir);EnsureDirectory(phraseDir);
            foreach(var blob in publishLocal){
                string path=Path.Combine(dictDir,blob.Hash+".tsv");GuardPath(path);
                if(File.Exists(path)){if(Hash(ReadBounded(path,8*MiB))!=blob.Hash)throw new IOException("共享词库校验失败；未覆盖原文件。");}
                else Atomic(path,blob.Bytes,false);
            }
            // Provider may change after staging: recheck local payloads before any local import.
            var now=LocalBlobs();
            if(!SameLocal(local,now)||File.Exists(LocalPhrases)!=phraseExisted||
               (phraseExisted&&!ReadBounded(LocalPhrases,MiB).SequenceEqual(originalPhraseBytes)))
                throw new IOException("本机词库或常用语已变化，请重新同步。");
            EnsureDirectory(LocalDictionaries);
            foreach(var blob in incoming){string path=Path.Combine(LocalDictionaries,blob.Hash+".tsv");FilePath(path);if(File.Exists(path))throw new IOException("本机目标词库已存在，未覆盖。");}
            for(int i=local.Count;i<combined.Count;i++){
                string target=Path.Combine(LocalDictionaries,combined[i].Hash+".tsv");GuardPath(target);GuardPath(staged[i]);File.Move(staged[i],target);
            }
            if(!phraseBytes.SequenceEqual(PhraseTSV(ReadLocalPhrases(LocalPhrases))))Atomic(LocalPhrases,phraseBytes,true);
            // Decisions enter live state only after the validated local merge succeeds.
            // A failed validation cannot hide a still-unresolved remote choice.
            ignoredVariants.Clear();ignoredVariants.UnionWith(nextIgnoredVariants);
            ignoredPhraseCodes.Clear();ignoredPhraseCodes.UnionWith(nextIgnoredCodes);
            PersistState(combined.Select(b=>b.Hash).ToHashSet(StringComparer.Ordinal),phrases.Keys.ToHashSet(StringComparer.Ordinal));
            CheckOwnSnapshot(ownSnapshot,originalOwnSnapshot);
            Atomic(ownSnapshot,snapshot,true); // Only this device's unchanged, validated UUID snapshot is replaced.
            return new(incoming.Count,added,conflicts.ToArray());
        }finally{
            GuardPath(stage);foreach(string file in Directory.EnumerateFiles(stage)){GuardPath(file);File.Delete(file);}Directory.Delete(stage);
        }
    }
    static void CheckOwnSnapshot(string path,byte[]? original){
        FilePath(path);
        if(File.Exists(path)!=(original!=null)||(original!=null&&!ReadBounded(path,MiB).SequenceEqual(original)))
            throw new IOException("本机设备快照已被同步客户端或其他程序修改，原文件保留；请重新同步。");
    }
    static bool SameLocal(List<DictionaryBlob> a,List<DictionaryBlob> b)=>a.Select(x=>(x.LocalPath,x.Hash)).SequenceEqual(b.Select(x=>(x.LocalPath,x.Hash)));
    void ValidateCore(IEnumerable<string> dictionaries,string phrases){
        IntPtr check=Core.lexi_create();if(check==IntPtr.Zero)throw new IOException("无法创建词库校验引擎。");
        try{
            // Fresh engine includes active builtin packs before ALL custom dictionaries.
            if(!Directory.Exists(data))throw new IOException("内置词库目录缺失，未导入。");
            string[] packs=Files(data,"*.tsv",128).Where(p=>{string n=Path.GetFileName(p);return n.Length>0&&n[0]>='0'&&n[0]<='9';}).ToArray();
            if(packs.Length==0)throw new IOException("内置词库缺失，未导入。");
            foreach(string path in packs.Concat(dictionaries)){
                GuardPath(path);if(Core.lexi_load(check,path)<0)throw new IOException("合并词库未通过校验："+Marshal.PtrToStringUTF8(Core.lexi_error(check)));
            }
            if(Core.lexi_load_phrases(check,phrases)<0)throw new IOException("常用语未通过校验："+Marshal.PtrToStringUTF8(Core.lexi_error(check)));
        }finally{Core.lexi_destroy(check);}
    }
}
