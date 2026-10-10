using System;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

// Built-in Windows recording API; no downloaded recording library.
// No microphone activation or upload before the user's explicit buttons.
internal sealed class VoiceCapture:IDisposable {
    [DllImport("winmm.dll",CharSet=CharSet.Unicode,EntryPoint="mciSendStringW")]
    static extern uint Send(string command,StringBuilder? result,int size,IntPtr callback);
    readonly string alias="lexi"+Guid.NewGuid().ToString("N");
    bool opened;
    static void Check(uint error){if(error!=0)throw new InvalidOperationException("录音失败，请检查麦克风设备和 Windows 麦克风隐私权限。");}
    internal void Start(){
        if(opened)throw new InvalidOperationException("录音已经开始。");
        Check(Send($"open new type waveaudio alias {alias}",null,0,IntPtr.Zero));opened=true;
        try {
            Check(Send($"set {alias} time format milliseconds bitspersample 16 channels 1 samplespersec 16000 bytespersec 32000 alignment 2",null,0,IntPtr.Zero));
            Check(Send($"record {alias} from 0 to 60000",null,0,IntPtr.Zero));
        }catch{Dispose();throw;}
    }
    internal string Stop(){
        if(!opened)throw new InvalidOperationException("尚未开始录音。");
        // A private, random temporary directory, never a document chosen by the user.
        var directory=Path.Combine(Path.GetTempPath(),"LexiVoice-"+Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);string path=Path.Combine(directory,"speech.wav");
        try {
            Check(Send($"stop {alias}",null,0,IntPtr.Zero));
            Check(Send($"save {alias} \"{path}\" wait",null,0,IntPtr.Zero));
            var bytes=new FileInfo(path).Length;
            if(bytes<=44||bytes>8*1024*1024)throw new InvalidOperationException("录音为空或超过 8 MB，请重试。");
            return path;
        }catch{Delete(path);throw;}finally{Dispose();}
    }
    internal static void Delete(string? path){
        if(path==null)return;
        if(File.Exists(path))File.Delete(path);
        var directory=Path.GetDirectoryName(path);
        if(directory!=null&&Directory.Exists(directory))Directory.Delete(directory,false);
    }
    public void Dispose(){if(opened){Send($"close {alias}",null,0,IntPtr.Zero);opened=false;}}
}

internal sealed class VoicePage:UserControl {
    readonly TextBox endpoint=new(){Width=620,PlaceholderText="个人服务的完整 HTTPS audio/transcriptions 地址"};
    readonly TextBox model=new(){Width=620,PlaceholderText="语音识别模型名称"};
    readonly ComboBox language=new(){Width=250,DropDownStyle=ComboBoxStyle.DropDownList};
    readonly CheckBox consent=new(){Text="允许将本次录音发送给上方个人服务（可能收费）",AutoSize=true};
    readonly TextBox transcript=new(){Width=620,Height=160,Multiline=true,ScrollBars=ScrollBars.Vertical};
    readonly Label status=new(){AutoSize=true,MaximumSize=new System.Drawing.Size(640,0)};
    readonly Button start=new(){Text="开始录音",AutoSize=true},stop=new(){Text="停止并保留录音",Enabled=false,AutoSize=true},upload=new(){Text="发送录音并识别（可能收费）",Enabled=false,AutoSize=true};
    readonly System.Windows.Forms.Timer deadline=new(){Interval=60000};
    readonly string config,keyFile;
    VoiceCapture? capture;string? audio;CancellationTokenSource? pending;
    bool sending;
    internal VoicePage(string root,string keyFile){
        this.keyFile=keyFile;config=Path.Combine(root,"voice.json");Dock=DockStyle.Fill;
        var flow=new FlowLayoutPanel{Dock=DockStyle.Fill,FlowDirection=FlowDirection.TopDown,WrapContents=false,AutoScroll=true,Padding=new Padding(24)};Controls.Add(flow);
        void Note(string text)=>flow.Controls.Add(new Label{Text=text,AutoSize=true,MaximumSize=new System.Drawing.Size(640,0),Margin=new Padding(3,8,3,12)});
        Note("语音输入 · 个人 API\n开始录音后才开启麦克风，最长 60 秒。停止后点击发送才上传。识别结果先预览，可修改后复制。Windows 版目前尚待实机测试。");
        Note("此功能需要兼容 audio/transcriptions 的个人服务；与译词 API 共用在云端辅助页保存的密钥。录音会临时存放在本机，完成、取消或关闭时删除；意外退出可能留下临时文件。");
        language.Items.AddRange(new object[]{"普通话","英语","日语","西班牙语"});language.SelectedIndex=0;
        flow.Controls.Add(endpoint);flow.Controls.Add(model);flow.Controls.Add(language);flow.Controls.Add(consent);
        var save=new Button{Text="保存语音配置",AutoSize=true};save.Click+=(_,_)=>{try{File.WriteAllText(config,JsonSerializer.Serialize(new{endpoint=endpoint.Text,model=model.Text,language=language.SelectedIndex}));status.Text="已保存；上传授权仅对当前会话有效。";}catch{status.Text="语音配置保存失败。";}};flow.Controls.Add(save);
        flow.Controls.Add(start);flow.Controls.Add(stop);flow.Controls.Add(upload);
        var cancel=new Button{Text="取消并删除本次录音",AutoSize=true};cancel.Click+=(_,_)=>Cancel();flow.Controls.Add(cancel);
        flow.Controls.Add(status);flow.Controls.Add(transcript);
        var copy=new Button{Text="复制识别文字",AutoSize=true};copy.Click+=(_,_)=>{if(!string.IsNullOrWhiteSpace(transcript.Text))Clipboard.SetText(transcript.Text);};flow.Controls.Add(copy);
        start.Click+=(_,_)=>Start();stop.Click+=(_,_)=>Stop();upload.Click+=async(_,_)=>await Upload();deadline.Tick+=(_,_)=>Stop();
        VisibleChanged+=(_,_)=>{if(!Visible)Cancel();};
        if(File.Exists(config)){try{using var json=JsonDocument.Parse(File.ReadAllText(config));endpoint.Text=json.RootElement.GetProperty("endpoint").GetString();model.Text=json.RootElement.GetProperty("model").GetString();language.SelectedIndex=Math.Clamp(json.RootElement.GetProperty("language").GetInt32(),0,3);}catch{status.Text="语音配置无法读取，请重新填写。";}}
    }
    void Start(){
        if(sending)return;Cancel();transcript.Clear();
        try{capture=new VoiceCapture();capture.Start();deadline.Start();start.Enabled=false;stop.Enabled=true;status.Text="正在录音 · 最长 60 秒 · 尚未上传";}
        catch(Exception ex){capture?.Dispose();capture=null;status.Text=ex.Message;}
    }
    void Stop(){
        deadline.Stop();if(capture==null)return;
        try{audio=capture.Stop();upload.Enabled=true;status.Text="录音已停止。检查服务地址后，可发送本次录音。";}
        catch(Exception ex){status.Text=ex.Message;}
        finally{capture.Dispose();capture=null;stop.Enabled=false;start.Enabled=true;}
    }
    async Task Upload(){
        if(sending||audio==null)return;
        if(!consent.Checked){status.Text="请先允许向你的个人服务发送本次录音。";return;}
        if(!Uri.TryCreate(endpoint.Text,UriKind.Absolute,out var uri)||uri.Scheme!="https"||uri.UserInfo.Length>0||uri.Query.Length>0||uri.Fragment.Length>0||string.IsNullOrWhiteSpace(model.Text)||!File.Exists(keyFile)){status.Text="请填写完整 HTTPS 地址、模型，并在云端辅助页保存密钥。";return;}
        string path=audio;audio=null;var cancellation=new CancellationTokenSource();pending=cancellation;sending=true;
        start.Enabled=false;upload.Enabled=false;status.Text="正在发送和识别…";
        try {
            using var handler=new HttpClientHandler{AllowAutoRedirect=false,UseCookies=false};using var client=new HttpClient(handler){Timeout=TimeSpan.FromSeconds(60)};
            using var request=new HttpRequestMessage(HttpMethod.Post,uri);request.Headers.Authorization=new AuthenticationHeaderValue("Bearer",Vault.Read(keyFile));
            using var form=new MultipartFormDataContent();form.Add(new StringContent(model.Text),"model");form.Add(new StringContent(new[]{"zh","en","ja","es"}[language.SelectedIndex]),"language");form.Add(new StringContent("json"),"response_format");
            var file=new ByteArrayContent(await File.ReadAllBytesAsync(path,cancellation.Token));file.Headers.ContentType=new MediaTypeHeaderValue("audio/wav");form.Add(file,"file","speech.wav");request.Content=form;
            using var response=await client.SendAsync(request,HttpCompletionOption.ResponseHeadersRead,cancellation.Token);if(!response.IsSuccessStatusCode)throw new InvalidOperationException("语音服务返回失败，请检查地址、模型和额度。");
            using var stream=await response.Content.ReadAsStreamAsync(cancellation.Token);using var buffer=new MemoryStream();var block=new byte[4096];int n;
            while((n=await stream.ReadAsync(block,cancellation.Token))>0){if(buffer.Length+n>65536)throw new InvalidOperationException("识别结果超过大小限制。");buffer.Write(block,0,n);}
            using var json=JsonDocument.Parse(buffer.ToArray());var text=json.RootElement.GetProperty("text").GetString();if(string.IsNullOrWhiteSpace(text)||text.Length>4000)throw new InvalidOperationException("语音服务没有返回可用文字。");
            if(!cancellation.IsCancellationRequested&&!IsDisposed){transcript.Text=text;status.Text="识别完成，请检查后复制。";}
        }catch(OperationCanceledException){if(!IsDisposed)status.Text="识别已取消或超时。";}
        catch{if(!IsDisposed)status.Text="语音识别失败，请检查服务配置和网络。";}
        finally {
            try{VoiceCapture.Delete(path);}catch{if(!IsDisposed)status.Text="临时录音清理失败，请检查系统临时目录中的 LexiVoice 文件夹。";}
            if(pending==cancellation)pending=null;cancellation.Dispose();sending=false;
            if(!IsDisposed)start.Enabled=true;
        }
    }
    internal void Cancel(){
        deadline.Stop();pending?.Cancel();capture?.Dispose();capture=null;
        try{VoiceCapture.Delete(audio);audio=null;status.Text="已取消，麦克风已关闭。";}catch{status.Text="临时录音清理失败，请检查系统临时目录中的 LexiVoice 文件夹。";}
        stop.Enabled=false;upload.Enabled=false;start.Enabled=!sending;transcript.Clear();
    }
    protected override void Dispose(bool disposing){if(disposing){Cancel();deadline.Dispose();}base.Dispose(disposing);}
}
