
    format PE GUI 5.0

;   =========================================================
    section '.code' code import writeable readable executable
;   =========================================================

    include 'win32ax.inc'

;   =====================
    include 'iat.imports'
;   =====================


;   =========================================================
;           GDI+ struct
;   =========================================================
struct GUID
    Data1                       rd 1
    Data2                       rw 1
    Data3                       rw 1
    Data4                       rb 8
ends

struct GdiplusStartupInput
    GdiplusVersion              rd 1
    DebugEventCallback          rd 1
    SuppressBackgroundThread    rd 1
    SuppressExternalCodecs      rd 1
ends

struct EncoderParameter 
    Guid                        GUID
    NumberOfValues              rd 1
    Type                        rd 1
    Value                       rd 1
ends

struct EncoderParameters
    Count                       rd 1
    Parameter                   EncoderParameter 1
ends

struct ImageCodecInfo
    Clsid                       rb 16
    FormatID                    rb 16
    CodecName                   rd 1
    DllName                     rd 1
    FormatDescription           rd 1
    FilenameExtension           rd 1
    MimeType                    rd 1
    Flags                       rd 1
    Version                     rd 1
    SigCount                    rd 1
    SizeSize                    rd 1
    SigPattern                  rd 1
    SigMask                     rd 1
ends


;   =========================================================
;           Копирование участка памяти
;
;   source      <- источник
;   dest        <- назначение
;   bytes       <- размер
;   =========================================================
proc _memcopy uses edi esi ecx, source, dest, bytes
    mov edi, [dest]
    mov esi, [source]
    mov ecx, [bytes]
    rep movsb
    ret
endp

;   =========================================================
;           Получение CLSID для энкодера
;
;   В целях сокращения кода, можно использовать заранее найденые значения CLSID:
;   PNG_CLSID GUID <0x557CF406>,<0x1A04>,<0x11D3>,<0x9A,0x73,0x00,0x00,0xF8,0x1E,0xF3,0x2E>
;   JPG_CLSID GUID <0x557CF401>,<0x1A04>,<0x11D3>,<0x9A,0x73,0x00,0x00,0xF8,0x1E,0xF3,0x2E>
;   BMP_CLSID GUID <0x557CF400>,<0x1A04>,<0x11D3>,<0x9A,0x73,0x00,0x00,0xF8,0x1E,0xF3,0x2E>
;   GIF_CLSID GUID <0x557CF402>,<0x1A04>,<0x11D3>,<0x9A,0x73,0x00,0x00,0xF8,0x1E,0xF3,0x2E>
;
;   http://msdn.microsoft.com/en-us/library/windows/desktop/ms533843%28v=vs.85%29.aspx
;   =========================================================
proc _GetEncoderClsid uses ecx ebx esi edi, mimeType, encClsid, mSize
    locals
        num                     rd 1
        size                    rd 1
    endl

    invoke GdipGetImageEncodersSize, addr num, addr size
    test eax, eax
    jne GECexit

    invoke VirtualAlloc, 0, [size], MEM_COMMIT, PAGE_READWRITE
    test eax, eax
    je GECexit
    mov ebx, eax

    invoke GdipGetImageEncoders, [num], [size], ebx
    test eax, eax
    jne GECexit

@@: mov esi, [ebx + ImageCodecInfo.MimeType]
    mov edi, [mimeType]
    mov ecx, [mSize]
    repe cmpsw
    je @f
    add ebx, sizeof.ImageCodecInfo
    dec [num]
    jnz @b
    jmp GECexit
@@: lea esi, [ebx + ImageCodecInfo.Clsid]
    mov edi, [encClsid]
    mov ecx, 4
    rep movsd
    invoke VirtualFree, ebx, 0, MEM_RELEASE
    ret

GECexit:
    xor eax, eax
    dec eax
    ret
endp

;   =========================================================
;           Делаем снимок экрана
;
;   mimeType    <- MIME-тип
;   filename    <- имя файла в формате UNICODE
;   quality     <- качество jpg. Для остальных форматов 0
;   mimeSize    <- размер MIME
;   =========================================================
proc _GetScreen uses ecx edx, mimeType, filename, quality, mimeSize
    locals
        encparams               EncoderParameters <>
        input                   GdiplusStartupInput <1>, <0>, <0>, <0>
        encClsid                GUID <>
        EncoderQuality          GUID <0x1d5be4b5>, <0xfa4a>, <0x452d>, <0x9c, 0xdd, 0x5d, 0xb3, 0x51, 0x05, 0xe7, 0xeb>
        token                   rd 1
        scrHeight               rd 1
        scrWidth                rd 1
        dc                      rd 1
        hbitmap                 rd 1
        hdc                     rd 1
        gdiBitmap               rd 1
        gdipMem                 rd 1
    endl

    invoke GdiplusStartup, addr token, addr input, NULL
    .if eax = 0

        invoke GetDC, HWND_DESKTOP
        .if eax <> 0
            mov [dc], eax

            invoke GetSystemMetrics, SM_CYSCREEN
            mov [scrHeight], eax

            invoke GetSystemMetrics, SM_CXSCREEN
            mov [scrWidth], eax

            invoke CreateCompatibleBitmap, [dc], [scrWidth], [scrHeight]
            .if eax <> 0
                mov [hbitmap], eax

                invoke CreateCompatibleDC, [dc]
                .if eax <> 0
                    mov [hdc], eax

                    invoke SelectObject, [hdc], [hbitmap]
                    .if eax <> 0

                        invoke BitBlt, [hdc], 0, 0, [scrWidth], [scrHeight], [dc], 0, 0, SRCCOPY
                        .if eax <> 0

                            invoke GdipCreateBitmapFromHBITMAP, [hbitmap], NULL, addr gdiBitmap
                            .if eax = 0

                                stdcall _GetEncoderClsid, [mimeType], addr encClsid, [mimeSize]
                                .if eax <> -1

                                    mov [encparams.Count], 1
                                    mov [encparams.Parameter.NumberOfValues], 1
                                    stdcall _memcopy, addr EncoderQuality, addr encparams.Parameter.Guid, sizeof.GUID
                                    mov [encparams.Parameter.Type], 4
                                    mov eax, [quality]
                                    mov [encparams.Parameter.Value], eax

                                    invoke GdipSaveImageToFile, [gdiBitmap], [filename], addr encClsid, addr encparams
                                    invoke GdipDisposeImage, [gdiBitmap]

                                .endif

                            .endif

                        .endif

                    .endif
                    invoke  DeleteObject, [hdc]

                .endif
                invoke  DeleteObject, [hbitmap]

            .endif
            invoke  ReleaseDC, HWND_DESKTOP, [dc]

        .endif
        invoke  GdiplusShutdown, [token]

    .endif
    ret
endp


;   =========================================================
;           ENTRY POINT
;   =========================================================
entry $

    stdcall _GetScreen, mimePng, png, 0, 10
    stdcall _GetScreen, mimeJpg, jpg, jpgQuality, 11
    stdcall _GetScreen, mimeBmp, bmp, 0, 10
    stdcall _GetScreen, mimeGif, gif, 0, 10

    invoke  ExitProcess, 0


    png                         du 'png.png', 0
    mimePng                     du 'image/png', 0

    jpg                         du 'jpg.jpg', 0
    mimeJpg                     du 'image/jpeg', 0

    bmp                         du 'bmp.bmp', 0
    mimeBmp                     du 'image/bmp', 0

    gif                         du 'gif.gif', 0
    mimeGif                     du 'image/gif', 0

    jpgQuality                  dd 100                  ; качество jpg
