import React, { useState, useRef } from 'react';
import { Save, FolderOpen, FileText } from 'lucide-react';
import '@toast-ui/editor/dist/toastui-editor.css';
import { Editor } from '@toast-ui/react-editor';

export default function App() {
  const defaultContent = '# 歡迎使用 Markdown 編輯器\n\n這是一個支援**所見即所得**的編輯器。\n\n- 支援 `.md` 與 `.txt` 格式\n- 可完全離線使用\n- 自動預設儲存為 `.md`\n- **您現在可以直接在右下角切換為「WYSIWYG」模式，直接編輯畫面！**';
  
  const [fileName, setFileName] = useState<string>('');
  const [fileExt, setFileExt] = useState<string>('.md');
  const [content, setContent] = useState<string>(defaultContent);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const editorRef = useRef<Editor>(null);

  const getAutoFileName = (text: string) => {
    const lines = text.split('\n').map(l => l.trim()).filter(l => l.length > 0);
    if (lines.length === 0) return 'Untitled';
    
    const firstLine = lines[0];
    const headingMatch = firstLine.match(/^#+\s+(.*)/);
    let name = '';
    
    if (headingMatch && headingMatch[1]) {
      name = headingMatch[1].trim();
    } else {
      name = firstLine.substring(0, 5).trim();
    }
    
    // 移除作業系統不允許的檔名字元
    return name.replace(/[/\\?%*:|"<>]/g, '-') || 'Untitled';
  };

  const autoFileName = getAutoFileName(content);

  const handleEditorChange = () => {
    if (editorRef.current) {
      setContent(editorRef.current.getInstance().getMarkdown());
    }
  };

  const handleOpen = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const nameParts = file.name.split('.');
    const ext = nameParts.length > 1 ? `.${nameParts.pop()}` : '.md';
    const name = nameParts.join('.');

    setFileName(name);
    setFileExt(ext.toLowerCase() === '.txt' ? '.txt' : '.md');

    const reader = new FileReader();
    reader.onload = (event) => {
      const newContent = event.target?.result as string;
      setContent(newContent);
      if (editorRef.current) {
        editorRef.current.getInstance().setMarkdown(newContent);
      }
    };
    reader.readAsText(file);
    
    if (fileInputRef.current) fileInputRef.current.value = '';
  };

  const handleSave = () => {
    const finalName = fileName.trim() || autoFileName;
    const currentContent = editorRef.current?.getInstance().getMarkdown() || content;
    const blob = new Blob([currentContent], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `${finalName}${fileExt}`;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  };

  return (
    <div className="flex flex-col h-screen bg-slate-50 text-slate-900 font-sans">
      <header className="flex flex-wrap items-center justify-between px-4 py-3 bg-white border-b border-slate-200 shadow-sm gap-4">
        <div className="flex items-center gap-2">
          <FileText className="w-6 h-6 text-emerald-600" />
          <h1 className="text-lg font-semibold tracking-tight">Markdown 編輯器</h1>
        </div>
        
        <div className="flex items-center gap-4 flex-wrap">
          <div className="flex items-center gap-2">
            <input 
              type="text" 
              value={fileName}
              onChange={(e) => setFileName(e.target.value)}
              className="px-3 py-1.5 border border-slate-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500 w-40 placeholder:text-slate-400"
              placeholder={autoFileName}
            />
            <select 
              value={fileExt}
              onChange={(e) => setFileExt(e.target.value)}
              className="px-3 py-1.5 border border-slate-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500 bg-white cursor-pointer"
            >
              <option value=".md">.md</option>
              <option value=".txt">.txt</option>
            </select>
          </div>

          <div className="flex items-center gap-2 border-l pl-4 border-slate-200">
            <input 
              type="file" 
              accept=".md,.txt" 
              className="hidden" 
              ref={fileInputRef}
              onChange={handleOpen}
            />
            <button 
              onClick={() => fileInputRef.current?.click()}
              className="flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-slate-700 bg-slate-100 hover:bg-slate-200 rounded-md transition-colors cursor-pointer"
            >
              <FolderOpen className="w-4 h-4" />
              開啟檔案
            </button>
            <button 
              onClick={handleSave}
              className="flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-white bg-emerald-600 hover:bg-emerald-700 rounded-md transition-colors cursor-pointer"
            >
              <Save className="w-4 h-4" />
              儲存檔案
            </button>
          </div>
        </div>
      </header>

      <main className="flex-1 overflow-hidden p-4 md:p-6">
        <div className="h-full rounded-xl overflow-hidden shadow-sm border border-slate-200 bg-white">
          <Editor
            ref={editorRef}
            initialValue={defaultContent}
            previewStyle="vertical"
            height="100%"
            initialEditType="markdown"
            useCommandShortcut={true}
            onChange={handleEditorChange}
            hideModeSwitch={false}
          />
        </div>
      </main>
    </div>
  );
}
