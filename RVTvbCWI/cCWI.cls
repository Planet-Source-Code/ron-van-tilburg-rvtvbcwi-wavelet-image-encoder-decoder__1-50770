VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
  Persistable = 0  'NotPersistable
  DataBindingBehavior = 0  'vbNone
  DataSourceBehavior  = 0  'vbNone
  MTSTransactionMode  = 0  'NotAnMTSObject
END
Attribute VB_Name = "cCWI"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False

Option Explicit
Option Base 0

'cCWI.cls  "Compressed Wavelet Image (.cwi) Encoder/Decoder Class"
'Copyright ©2004 Ron van Tilburg , free use of code for educational purposes
'for commercial interests please approach author, this code is not public domain
'========================================================================================================
'This is a completely original Image format based on using a Wavelet Transform to compress an image
'Similar to JPGs in approach, this can also save a LOSSLESS variety of file when Quality=100
'
'"Any similarity to other copyrighted Image Encoders/Decoders is entirely coincidental"
'
'Compression can be impressive at the expense of quality (of course). Encoding is considerably
'slower than Decoding. See in the Body of the Class for Methods and Algorithms and further notes
'By comparison with JPEGs the time to encode and decode is 10-15 times longer
'
'     RVT 4 Jan 2004 (rivit@f1.net.au)
'
'=====================================================================================================================
'A compressed Wavelet Image *.cwi   Image Format ©2004 Ron van Tilburg -
'=====================================================================================================================

Public Enum CWI_FLAGS               'How to Handle colour Flags (default is YCbCr)
  CWI_RGB = 0
  CWI_GREYSCALE = 3
  CWI_YCbCr = 2
End Enum

Public Enum CWI_TRANSFORM           'Which Transform to use 1 is faster, 4 is more smoothing
  CWI_T11 = 1                       '(1,1) or Haar Transform
  CWI_T22 = 2                       '(2,2) Transform
  CWI_T44 = 3                       '(4,4) Transform
End Enum

Private Type CWIHdr
  Tag               As Long         '#CWI
  Size              As Long         'Size of entire File
  Version           As Byte         'Version  01
  Revision          As Byte         'Revision 01
  Transform         As Byte         '(2,2) Transform = 02
  flags             As Byte         'CWI_Flags
  Width             As Integer      'Pic Width
  Height            As Integer      'Pic Height
  nRC               As Integer      'Dimension of XBlock (Nr of Rows and Columns)
  Quality           As Byte         'Quality 1-100  100=Lossless (8 bitplanes), 1 is pretty ordinary
  MaxBits           As Byte         'Nr of Bits Maximally (usually 8)
  LenCoeffs         As Long         'Length of Coefficient Bits
  LenComment        As Long         'Length of ASCII Comment (null terminated)
End Type

Private Type CWI                    'A complete File
  Header            As CWIHdr
  Coeffs()          As Byte         'Coeffs Array is acually Below
  Comment()         As Byte         'Comment Array Below
End Type

'==============================================================================================================
Private zCWIHdr     As CWIHdr       'Our Class Image Header
Private zCoeffs()   As Byte         'Encoded Coefficients
Private zComment()  As Byte         'ASCII String
'--------------------------------------------------------------------------------------------------------------
Private BitMask     As Byte         'used during BITIO
Private CPtr        As Long         'Byte Ptr

Private TwoP(31)    As Long         'Powers of two  2^P
Private TwoR(31)    As Long         'Powers of two  2^(R-1)
Private TwoB(255)   As Byte         'The number of bits in value
'--------------------------------------------------------------------------------------------------------------
Private Type XBlock                 'used during Encoding/Decoding
  val()  As Integer
  sign() As Byte
  mark() As Byte
  dmax() As Long
  gmax() As Long
End Type

Private Type InvRC                  'used for coefficient index lookup
  i As Integer
  j As Integer
End Type
'--------------------------------------------------------------------------------------------------------------

' constants/variables used specifically in the Encode/Decode Routines
Private Const MIP As Long = 0     'insignificant or untested
Private Const MNP As Long = 1     'newly significant
Private Const MSP As Long = 2     'significant
Private Const MCP As Long = 3     'like MIP but used during IS Pass
Private Const MD  As Long = 4     'first child in a descendant group
Private Const MG  As Long = 5     'first grandchild
Private Const MN2 As Long = 6     '1st grand child set of MD
Private Const MN3 As Long = 7     '2nd grand child set
Private Const MN4 As Long = 8     '3rd grand child
Private Const MN5 As Long = 9     '4th
Private Const MN6 As Long = 10    '5th
Private Const MN7 As Long = 11    '6th
Private Const MN8 As Long = 12    '7th

'-----------------------------------------------------------------------------------------------------------------
'API constants
Private Const OBJ_BITMAP As Long = 7      'GetCurrentObject

Private Const BI_RGB          As Long = 0
Private Const DIB_RGB_COLORS  As Long = 0

'Variable types needed for DIBSections.
Private Type SAFEARRAYBOUND
  cElements         As Long
  lLbound           As Long
End Type

Private Type SAFEARRAY
  cDims             As Integer
  fFeatures         As Integer
  cbElements        As Long
  cLocks            As Long
  pvData            As Long
  Bounds(0)         As SAFEARRAYBOUND
End Type

Private Type RGBQUAD
  rgbBlue           As Byte
  rgbGreen          As Byte
  rgbRed            As Byte
  rgbReserved       As Byte
End Type

Private Type BITMAPINFOHEADER
  biSize            As Long
  biWidth           As Long
  biHeight          As Long
  biPlanes          As Integer
  biBitCount        As Integer
  biCompression     As Long
  biSizeImage       As Long
  biXPelsPerMeter   As Long
  biYPelsPerMeter   As Long
  biClrUsed         As Long
  biClrImportant    As Long
End Type

Private Type BITMAPINFO
  bmiHeader         As BITMAPINFOHEADER
  bmiColors         As RGBQUAD
End Type

'Used in Creating a StdPicture
Private Type GUID
  Data1 As Long
  Data2 As Integer
  Data3 As Integer
  Data4(7) As Byte
End Type

Private Type PictDesc
  Size As Long
Type As Long
  hBmp As Long
  hPal As Long
End Type

'API needed for creating DIBSections for sampling and pixel access.
Private Declare Function GetCurrentObject Lib "gdi32" (ByVal hDC As Long, ByVal uObjectType As Long) As Long
Private Declare Function GetObject Lib "gdi32" Alias "GetObjectA" (ByVal hObject As Long, ByVal nCount As Long, ByRef lpObject As Any) As Long
Private Declare Function CreateCompatibleDC Lib "gdi32" (ByVal hDC As Long) As Long
Private Declare Function CreateDIBSection2 Lib "gdi32" Alias "CreateDIBSection" (ByVal hDC As Long, pBitmapInfo As BITMAPINFO, ByVal un As Long, lplpVoid As Long, ByVal handle As Long, ByVal dw As Long) As Long   'lplpVoid changed to ByRef
Private Declare Function BitBlt Lib "gdi32" (ByVal hDestDC As Long, ByVal x As Long, ByVal y As Long, ByVal nWidth As Long, ByVal nHeight As Long, ByVal hSrcDC As Long, ByVal xSrc As Long, ByVal ySrc As Long, ByVal dwRop As Long) As Long
Private Declare Function SelectObject Lib "gdi32" (ByVal hDC As Long, ByVal hObject As Long) As Long
Private Declare Function DeleteObject Lib "gdi32" (ByVal hObject As Long) As Long
Private Declare Function DeleteDC Lib "gdi32" (ByVal hDC As Long) As Long
Private Declare Function VarPtrArray Lib "msvbvm60.dll" Alias "VarPtr" (Ptr() As Any) As Long
Private Declare Sub CopyMemory Lib "kernel32" Alias "RtlMoveMemory" (lpvDest As Any, lpvSource As Any, ByVal cbCopy As Long)
Private Declare Function OleCreatePictureIndirect Lib "olepro32" (lpPictDesc As PictDesc, riid As Any, ByVal fPictureOwnsHandle As Long, iPic As IPicture) As Long

'=====================================================================================================================
'              2D   I N T E G E R   D I S C R E T E   W A V E L E T   T R A N S F O R M A T I O N
'=====================================================================================================================
' from the work WAVELET TRANSFORMS THAT MAP INTEGERS TO INTEGERS
' by A. R. CALDERBANK, INGRID DAUBECHIES, WIM SWELDENS, AND BOON-LOCK YEO
' August 1996

'The transforms below have been optimised somewhat to speed them up. As a consequnece they look pretty weird.
'The entire image array, using all color components is transformed in one pass over all rows and columns.

'Lifted Wavelet (1,1) aka. Haar or S Transform
'  d1,L = s0,2L+1 - s0,2L
'  s1,L = s0,2L + (d1,L/2)
Private Sub Fwd_LWT_11_2D(ByRef z() As Integer, ByRef MinP As Long, ByRef MinQ As Long)  'bounds(z) must be multiple of 2

 Dim p As Long, q As Long, r As Long, n As Long, m As Long, i As Long, k As Long

  p = UBound(z, 1) + 1  'y                                              'Find a 2 modulo that is the same in both
  q = UBound(z, 2) + 1  'x                                              'directions; will be at least 8x8
  Do While (p > 2 And (p And 1) = 0) And (q > 2 And (q And 1) = 0)
    p = p \ 2: q = q \ 2
  Loop
  MinP = p: MinQ = q

  r = UBound(z, 1)
  Do While r >= 0
    m = UBound(z, 2) + 1
    n = m
    k = 2
    Do While m > MinQ
      p = 0
      q = k \ 2

      For i = 1 To n \ k
        z(r, q) = z(r, q) - z(r, p)
        z(r, p) = z(r, p) + z(r, q) \ 2
        p = p + k
        q = q + k
      Next i

      k = k + k
      m = m \ 2                     'next level
    Loop
    r = r - 1
  Loop

  r = UBound(z, 2)
  Do While r >= 0
    m = UBound(z, 1) + 1
    n = m
    k = 2
    Do While m > MinP
      's()=z(0 to m\2-1)
      'd()=z(m\2 to m-1)
      p = 0
      q = k \ 2

      For i = 1 To n \ k
        z(q, r) = z(q, r) - z(p, r)
        z(p, r) = z(p, r) + z(q, r) \ 2
        p = p + k
        q = q + k
      Next i

      k = k + k
      m = m \ 2                     'next level
    Loop
    r = r - 1
  Loop

End Sub

'In reverse we start at the top of the array and work backwards.
'The lifted transform inverse is sign and component reversed when compared to the forward transform

'Inverse Lifted Wavelet (1,1) Transform
's0,2L = s1,L - d1,L/2
's0,2L+1 = d1,L + s0,2L
Private Sub Inv_LWT_11_2D(ByRef z() As Integer, ByVal MinP As Long, ByVal MinQ As Long)

 Dim p As Long, q As Long, r As Long, n As Long, m As Long, i As Long, k As Long

  r = UBound(z, 2)
  Do While r >= 0
    n = UBound(z, 1) + 1
    m = MinP
    k = n \ MinP
    Do While m < n

      q = n - k \ 2
      p = n - k

      For i = 1 To n \ k
        z(p, r) = z(p, r) - z(q, r) \ 2
        z(q, r) = z(q, r) + z(p, r)
        p = p - k
        q = q - k
      Next i

      k = k \ 2
      m = m + m                       'next level
    Loop
    r = r - 1
  Loop

  r = UBound(z, 1)
  Do While r >= 0
    n = UBound(z, 2) + 1
    m = MinQ
    k = n \ MinQ
    Do While m < n

      q = n - k \ 2
      p = n - k

      For i = 1 To n \ k
        z(r, p) = z(r, p) - z(r, q) \ 2
        z(r, q) = z(r, q) + z(r, p)
        p = p - k
        q = q - k
      Next i

      k = k \ 2
      m = m + m                       'next level
    Loop
    r = r - 1
  Loop

End Sub

'Lifted Wavelet (2,2) Interpolating Transform
Private Sub Fwd_LWT_22_2D(ByRef z() As Integer, ByRef MinP As Long, ByRef MinQ As Long)  'bounds(z) must be multiple of 2

 Dim p As Long, q As Long, r As Long, n As Long, m As Long, i As Long, k As Long
 Dim s00 As Long, sp1 As Long, d00 As Long, dm1 As Long

  p = UBound(z, 1) + 1  'y
  q = UBound(z, 2) + 1  'x
  Do While (p > 2 And (p And 1) = 0) And (q > 2 And (q And 1) = 0)
    p = p \ 2: q = q \ 2
  Loop
  MinP = p: MinQ = q

  r = UBound(z, 1)
  Do While r >= 0
    m = UBound(z, 2) + 1
    n = m
    k = 2
    Do While m > MinQ
      's()=z(0 to m\2-1)
      'd()=z(m\2 to m-1)
      p = 0
      q = k \ 2

      dm1 = 0: d00 = z(r, q)
      s00 = z(r, p): sp1 = z(r, p + k)
      d00 = d00 - (s00 + sp1 + 1) \ 2
      s00 = s00 + (dm1 + d00 + 2) \ 4
      z(r, q) = d00: z(r, p) = s00
      p = p + k
      q = q + k

      For i = 1 To n \ k - 2
        '        z(r, q) = z(r, q) - (z(r, p) + z(r, p + k) + 1) \ 2
        '        z(r, p) = z(r, p) + (z(r, q - k) + z(r, q) + 2) \ 4
        dm1 = d00: d00 = z(r, q)
        s00 = sp1: sp1 = z(r, p + k)
        d00 = d00 - (s00 + sp1 + 1) \ 2
        s00 = s00 + (dm1 + d00 + 2) \ 4
        z(r, q) = d00: z(r, p) = s00
        p = p + k
        q = q + k
      Next i

      dm1 = d00: d00 = z(r, q)
      s00 = sp1: sp1 = 0
      d00 = d00 - (s00 + sp1 + 1) \ 2
      s00 = s00 + (dm1 + d00 + 2) \ 4
      z(r, q) = d00: z(r, p) = s00

      k = k + k
      m = m \ 2                     'next level
    Loop
    r = r - 1
  Loop

  r = UBound(z, 2)
  Do While r >= 0
    m = UBound(z, 1) + 1
    n = m
    k = 2
    Do While m > MinP
      's()=z(0 to m\2-1)
      'd()=z(m\2 to m-1)
      p = 0
      q = k \ 2

      dm1 = 0: d00 = z(q, r)
      s00 = z(p, r): sp1 = z(p + k, r)
      d00 = d00 - (s00 + sp1 + 1) \ 2
      s00 = s00 + (dm1 + d00 + 2) \ 4
      z(q, r) = d00: z(p, r) = s00
      p = p + k
      q = q + k

      For i = 1 To n \ k - 2
        '        z(q, r) = z(q, r) - (z(p, r) + z(p + k, r) + 1) \ 2
        '        z(p, r) = z(p, r) + (z(q - k, r) + z(q, r) + 2) \ 4
        dm1 = d00: d00 = z(q, r)
        s00 = sp1: sp1 = z(p + k, r)
        d00 = d00 - (s00 + sp1 + 1) \ 2
        s00 = s00 + (dm1 + d00 + 2) \ 4
        z(q, r) = d00: z(p, r) = s00
        p = p + k
        q = q + k
      Next i

      dm1 = d00: d00 = z(q, r)
      s00 = sp1: sp1 = 0
      d00 = d00 - (s00 + sp1 + 1) \ 2
      s00 = s00 + (dm1 + d00 + 2) \ 4
      z(q, r) = d00: z(p, r) = s00

      k = k + k
      m = m \ 2                     'next level
    Loop
    r = r - 1
  Loop

End Sub

'Inverse Lifted Wavelet (2,2) Interpolating Transform
Private Sub Inv_LWT_22_2D(ByRef z() As Integer, ByVal MinP As Long, ByVal MinQ As Long)

 Dim p As Long, q As Long, r As Long, n As Long, m As Long, i As Long, k As Long
 Dim s00 As Long, sp1 As Long, d00 As Long, dm1 As Long

  r = UBound(z, 2)
  Do While r >= 0
    n = UBound(z, 1) + 1
    m = MinP
    k = n \ MinP
    Do While m < n
      's()=z(0 to m\2-1)
      'd()=z(m\2 to m-1)

      q = n - k \ 2
      p = n - k

      s00 = z(p, r): sp1 = 0
      d00 = z(q, r): dm1 = z(q - k, r)
      s00 = s00 - (dm1 + d00 + 2) \ 4
      d00 = d00 + (s00 + sp1 + 1) \ 2
      z(p, r) = s00: z(q, r) = d00
      p = p - k
      q = q - k

      For i = 1 To n \ k - 2
        '        z(p, r) = z(p, r) - (z(q - k, r) + z(q, r) + 2) \ 4
        '        z(q, r) = z(q, r) + (z(p, r) + z(p + k, r) + 1) \ 2
        sp1 = s00: s00 = z(p, r)
        d00 = dm1: dm1 = z(q - k, r)
        s00 = s00 - (dm1 + d00 + 2) \ 4
        d00 = d00 + (s00 + sp1 + 1) \ 2
        z(p, r) = s00: z(q, r) = d00
        p = p - k
        q = q - k
      Next i

      sp1 = s00: s00 = z(p, r)
      d00 = dm1: dm1 = 0
      s00 = s00 - (dm1 + d00 + 2) \ 4
      d00 = d00 + (s00 + sp1 + 1) \ 2
      z(p, r) = s00: z(q, r) = d00

      k = k \ 2
      m = m + m                       'next level
    Loop
    r = r - 1
  Loop

  r = UBound(z, 1)
  Do While r >= 0
    n = UBound(z, 2) + 1
    m = MinQ
    k = n \ MinQ
    Do While m < n
      's()=z(0 to m\2-1)
      'd()=z(m\2 to m-1)

      q = n - k \ 2
      p = n - k

      s00 = z(r, p): sp1 = 0
      d00 = z(r, q): dm1 = z(r, q - k)
      s00 = s00 - (dm1 + d00 + 2) \ 4
      d00 = d00 + (s00 + sp1 + 1) \ 2
      z(r, p) = s00: z(r, q) = d00
      p = p - k
      q = q - k

      For i = 1 To n \ k - 2
        '        z(r, p) = z(r, p) - (z(r, q - k) + z(r, q) + 2) \ 4
        '        z(r, q) = z(r, q) + (z(r, p) + z(r, p + k) + 1) \ 2
        sp1 = s00: s00 = z(r, p)
        d00 = dm1: dm1 = z(r, q - k)
        s00 = s00 - (dm1 + d00 + 2) \ 4
        d00 = d00 + (s00 + sp1 + 1) \ 2
        z(r, p) = s00: z(r, q) = d00
        p = p - k
        q = q - k
      Next i

      sp1 = s00: s00 = z(r, p)
      d00 = dm1: dm1 = 0
      s00 = s00 - (dm1 + d00 + 2) \ 4
      d00 = d00 + (s00 + sp1 + 1) \ 2
      z(r, p) = s00: z(r, q) = d00

      k = k \ 2
      m = m + m                       'next level
    Loop
    r = r - 1
  Loop

End Sub

'Lifted Wavelet (4,4) Interpolating Transform
Private Sub Fwd_LWT_44_2D(ByRef z() As Integer, ByRef MinP As Long, ByRef MinQ As Long)  'bounds(z) must be multiple of 4

 Dim p As Long, q As Long, r As Long, n As Long, m As Long, i As Long, k As Long
 Dim sm1 As Long, s00 As Long, sp1 As Long, sp2 As Long, sz As Long
 Dim dm2 As Long, dm1 As Long, d00 As Long, dp1 As Long, dz As Long

  p = UBound(z, 1) + 1  'y
  q = UBound(z, 2) + 1  'x
  Do While (p > 4 And (p And 1) = 0) And (q > 4 And (q And 1) = 0)
    p = p \ 2: q = q \ 2
  Loop
  MinP = p: MinQ = q

  r = UBound(z, 1)
  Do While r >= 0
    m = UBound(z, 2) + 1
    n = m
    k = 2
    Do While m > MinQ
      's()=z(0 to m\2-1)
      'd()=z(m\2 to m-1)
      p = 0
      q = k \ 2

      dm2 = 0: dm1 = 0:       d00 = z(r, q):     dp1 = z(r, q + k)
      sm1 = 0: s00 = z(r, p): sp1 = z(r, p + k): sp2 = z(r, p + k + k)
      sz = s00 + sp1: sz = 8 * sz + sz:         d00 = d00 - (sz - sm1 - sp2 + 8) \ 16
      dz = dm1 + d00: dz = 8 * dz + dz:         s00 = s00 + (dz - dm2 - dp1 + 8) \ 16
      z(r, q) = d00: z(r, p) = s00
      p = p + k
      q = q + k

      dm2 = dm1: dm1 = d00: d00 = dp1: dp1 = z(r, q + k)
      sm1 = s00: s00 = sp1: sp1 = sp2: sp2 = z(r, p + k + k)
      sz = s00 + sp1: sz = 8 * sz + sz:         d00 = d00 - (sz - sm1 - sp2 + 8) \ 16
      dz = dm1 + d00: dz = 8 * dz + dz:         s00 = s00 + (dz - dm2 - dp1 + 8) \ 16
      z(r, q) = d00: z(r, p) = s00
      p = p + k
      q = q + k

      For i = 1 To n \ k - 4
        '        z(r, q) = z(r, q) - (9 * (z(r, p) + z(r, p + k)) - (z(r, p - k) + z(r, p + k + k)) + 8) \ 16
        '        z(r, p) = z(r, p) + (9 * (z(r, q - k) + z(r, q)) - (z(r, q - k - k) + z(r, q + k)) + 8) \ 16
        dm2 = dm1: dm1 = d00: d00 = dp1: dp1 = z(r, q + k)
        sm1 = s00: s00 = sp1: sp1 = sp2: sp2 = z(r, p + k + k)
        sz = s00 + sp1: sz = 8 * sz + sz:         d00 = d00 - (sz - sm1 - sp2 + 8) \ 16
        dz = dm1 + d00: dz = 8 * dz + dz:         s00 = s00 + (dz - dm2 - dp1 + 8) \ 16
        z(r, q) = d00: z(r, p) = s00
        p = p + k
        q = q + k
      Next i

      dm2 = dm1: dm1 = d00: d00 = dp1: dp1 = z(r, q + k)
      sm1 = s00: s00 = sp1: sp1 = sp2: sp2 = 0
      sz = s00 + sp1: sz = 8 * sz + sz:         d00 = d00 - (sz - sm1 - sp2 + 8) \ 16
      dz = dm1 + d00: dz = 8 * dz + dz:         s00 = s00 + (dz - dm2 - dp1 + 8) \ 16
      z(r, q) = d00: z(r, p) = s00
      p = p + k
      q = q + k

      dm2 = dm1: dm1 = d00: d00 = dp1: dp1 = 0
      sm1 = s00: s00 = sp1: sp1 = sp2: sp2 = 0
      sz = s00 + sp1: sz = 8 * sz + sz:         d00 = d00 - (sz - sm1 - sp2 + 8) \ 16
      dz = dm1 + d00: dz = 8 * dz + dz:         s00 = s00 + (dz - dm2 - dp1 + 8) \ 16
      z(r, q) = d00: z(r, p) = s00

      k = k + k
      m = m \ 2                     'next level
    Loop
    r = r - 1
  Loop

  r = UBound(z, 2)
  Do While r >= 0
    m = UBound(z, 1) + 1
    n = m
    k = 2
    Do While m > MinP
      's()=z(0 to m\2-1)
      'd()=z(m\2 to m-1)
      p = 0
      q = k \ 2

      dm2 = 0: dm1 = 0:       d00 = z(q, r):     dp1 = z(q + k, r)
      sm1 = 0: s00 = z(p, r): sp1 = z(p + k, r): sp2 = z(p + k + k, r)
      sz = s00 + sp1: sz = 8 * sz + sz:         d00 = d00 - (sz - sm1 - sp2 + 8) \ 16
      dz = dm1 + d00: dz = 8 * dz + dz:         s00 = s00 + (dz - dm2 - dp1 + 8) \ 16
      z(q, r) = d00: z(p, r) = s00
      p = p + k
      q = q + k

      dm2 = dm1: dm1 = d00: d00 = dp1: dp1 = z(q + k, r)
      sm1 = s00: s00 = sp1: sp1 = sp2: sp2 = z(p + k + k, r)
      sz = s00 + sp1: sz = 8 * sz + sz:         d00 = d00 - (sz - sm1 - sp2 + 8) \ 16
      dz = dm1 + d00: dz = 8 * dz + dz:         s00 = s00 + (dz - dm2 - dp1 + 8) \ 16
      z(q, r) = d00: z(p, r) = s00
      p = p + k
      q = q + k

      For i = 1 To n \ k - 4
        '        z(q, r) = z(q, r) - (9 * (z(p, r) + z(p + k, r)) - (z(p - k, r) + z(p + k + k, r)) + 8) \ 16
        '        z(p, r) = z(p, r) + (9 * (z(q - k, r) + z(q, r)) - (z(q - k - k, r) + z(q + k, r)) + 8) \ 16
        dm2 = dm1: dm1 = d00: d00 = dp1: dp1 = z(q + k, r)
        sm1 = s00: s00 = sp1: sp1 = sp2: sp2 = z(p + k + k, r)
        sz = s00 + sp1: sz = 8 * sz + sz:         d00 = d00 - (sz - sm1 - sp2 + 8) \ 16
        dz = dm1 + d00: dz = 8 * dz + dz:         s00 = s00 + (dz - dm2 - dp1 + 8) \ 16
        z(q, r) = d00: z(p, r) = s00
        p = p + k
        q = q + k
      Next i

      dm2 = dm1: dm1 = d00: d00 = dp1: dp1 = z(q + k, r)
      sm1 = s00: s00 = sp1: sp1 = sp2: sp2 = 0
      sz = s00 + sp1: sz = 8 * sz + sz:         d00 = d00 - (sz - sm1 - sp2 + 8) \ 16
      dz = dm1 + d00: dz = 8 * dz + dz:         s00 = s00 + (dz - dm2 - dp1 + 8) \ 16
      z(q, r) = d00: z(p, r) = s00
      p = p + k
      q = q + k

      dm2 = dm1: dm1 = d00: d00 = dp1: dp1 = 0
      sm1 = s00: s00 = sp1: sp1 = sp2: sp2 = 0
      sz = s00 + sp1: sz = 8 * sz + sz:         d00 = d00 - (sz - sm1 - sp2 + 8) \ 16
      dz = dm1 + d00: dz = 8 * dz + dz:         s00 = s00 + (dz - dm2 - dp1 + 8) \ 16
      z(q, r) = d00: z(p, r) = s00

      k = k + k
      m = m \ 2                     'next level
    Loop
    r = r - 1
  Loop

End Sub

'Inverse Lifted Wavelet Interpolating (4,4) Transform
Private Sub Inv_LWT_44_2D(ByRef z() As Integer, ByVal MinP As Long, ByVal MinQ As Long)

 Dim p As Long, q As Long, r As Long, n As Long, m As Long, i As Long, k As Long
 Dim sm1 As Long, s00 As Long, sp1 As Long, sp2 As Long, sz As Long
 Dim dm2 As Long, dm1 As Long, d00 As Long, dp1 As Long, dz As Long

  r = UBound(z, 2)
  Do While r >= 0
    n = UBound(z, 1) + 1
    m = MinP
    k = n \ MinP
    Do While m < n
      's()=z(0 to m\2-1)
      'd()=z(m\2 to m-1)

      q = n - k \ 2
      p = n - k

      dp1 = 0: d00 = z(q, r): dm1 = z(q - k, r): dm2 = z(q - k - k, r)
      sp2 = 0: sp1 = 0:       s00 = z(p, r):     sm1 = z(p - k, r)
      dz = dm1 + d00: dz = 8 * dz + dz:         s00 = s00 - (dz - dm2 - dp1 + 8) \ 16
      sz = s00 + sp1: sz = 8 * sz + sz:         d00 = d00 + (sz - sm1 - sp2 + 8) \ 16
      z(q, r) = d00: z(p, r) = s00
      p = p - k
      q = q - k

      dp1 = d00: d00 = dm1: dm1 = dm2: dm2 = z(q - k - k, r)
      sp2 = sp1: sp1 = s00: s00 = sm1: sm1 = z(p - k, r)
      dz = dm1 + d00: dz = 8 * dz + dz:         s00 = s00 - (dz - dm2 - dp1 + 8) \ 16
      sz = s00 + sp1: sz = 8 * sz + sz:         d00 = d00 + (sz - sm1 - sp2 + 8) \ 16
      z(q, r) = d00: z(p, r) = s00
      p = p - k
      q = q - k

      For i = 1 To n \ k - 4
        '        z(p, r) = z(p, r) - (9 * (z(q - k, r) + z(q, r)) - (z(q - k - k, r) + z(q + k, r)) + 8) \ 16
        '        z(q, r) = z(q, r) + (9 * (z(p, r) + z(p + k, r)) - (z(p - k, r) + z(p + k + k, r)) + 8) \ 16
        dp1 = d00: d00 = dm1: dm1 = dm2: dm2 = z(q - k - k, r)
        sp2 = sp1: sp1 = s00: s00 = sm1: sm1 = z(p - k, r)
        dz = dm1 + d00: dz = 8 * dz + dz:         s00 = s00 - (dz - dm2 - dp1 + 8) \ 16
        sz = s00 + sp1: sz = 8 * sz + sz:         d00 = d00 + (sz - sm1 - sp2 + 8) \ 16
        z(q, r) = d00: z(p, r) = s00
        p = p - k
        q = q - k
      Next i

      dp1 = d00: d00 = dm1: dm1 = dm2: dm2 = 0
      sp2 = sp1: sp1 = s00: s00 = sm1: sm1 = z(p - k, r)
      dz = dm1 + d00: dz = 8 * dz + dz:         s00 = s00 - (dz - dm2 - dp1 + 8) \ 16
      sz = s00 + sp1: sz = 8 * sz + sz:         d00 = d00 + (sz - sm1 - sp2 + 8) \ 16
      z(q, r) = d00: z(p, r) = s00
      p = p - k
      q = q - k

      dp1 = d00: d00 = dm1: dm1 = dm2: dm2 = 0
      sp2 = sp1: sp1 = s00: s00 = sm1: sm1 = 0
      dz = dm1 + d00: dz = 8 * dz + dz:         s00 = s00 - (dz - dm2 - dp1 + 8) \ 16
      sz = s00 + sp1: sz = 8 * sz + sz:         d00 = d00 + (sz - sm1 - sp2 + 8) \ 16
      z(q, r) = d00: z(p, r) = s00

      k = k \ 2
      m = m + m                       'next level
    Loop
    r = r - 1
  Loop

  r = UBound(z, 1)
  Do While r >= 0
    n = UBound(z, 2) + 1
    m = MinQ
    k = n \ MinQ
    Do While m < n
      's()=z(0 to m\2-1)
      'd()=z(m\2 to m-1)

      q = n - k \ 2
      p = n - k

      dp1 = 0: d00 = z(r, q): dm1 = z(r, q - k): dm2 = z(r, q - k - k)
      sp2 = 0: sp1 = 0:       s00 = z(r, p):    sm1 = z(r, p - k)
      dz = dm1 + d00: dz = 8 * dz + dz:         s00 = s00 - (dz - dm2 - dp1 + 8) \ 16
      sz = s00 + sp1: sz = 8 * sz + sz:         d00 = d00 + (sz - sm1 - sp2 + 8) \ 16
      z(r, q) = d00: z(r, p) = s00
      p = p - k
      q = q - k

      dp1 = d00: d00 = dm1: dm1 = dm2: dm2 = z(r, q - k - k)
      sp2 = sp1: sp1 = s00: s00 = sm1: sm1 = z(r, p - k)
      dz = dm1 + d00: dz = 8 * dz + dz:         s00 = s00 - (dz - dm2 - dp1 + 8) \ 16
      sz = s00 + sp1: sz = 8 * sz + sz:         d00 = d00 + (sz - sm1 - sp2 + 8) \ 16
      z(r, q) = d00: z(r, p) = s00
      p = p - k
      q = q - k

      For i = 1 To n \ k - 4
        '        z(r, p) = z(r, p) - (9 * (z(r, q - k) + z(r, q)) - (z(r, q - k - k) + z(r, q + k)) + 8) \ 16
        '        z(r, q) = z(r, q) + (9 * (z(r, p) + z(r, p + k)) - (z(r, p - k) + z(r, p + k + k)) + 8) \ 16
        dp1 = d00: d00 = dm1: dm1 = dm2: dm2 = z(r, q - k - k)
        sp2 = sp1: sp1 = s00: s00 = sm1: sm1 = z(r, p - k)
        dz = dm1 + d00: dz = 8 * dz + dz:         s00 = s00 - (dz - dm2 - dp1 + 8) \ 16
        sz = s00 + sp1: sz = 8 * sz + sz:         d00 = d00 + (sz - sm1 - sp2 + 8) \ 16
        z(r, q) = d00: z(r, p) = s00
        p = p - k
        q = q - k
      Next i

      dp1 = d00: d00 = dm1: dm1 = dm2: dm2 = 0
      sp2 = sp1: sp1 = s00: s00 = sm1: sm1 = z(r, p - k)
      dz = dm1 + d00: dz = 8 * dz + dz:         s00 = s00 - (dz - dm2 - dp1 + 8) \ 16
      sz = s00 + sp1: sz = 8 * sz + sz:         d00 = d00 + (sz - sm1 - sp2 + 8) \ 16
      z(r, q) = d00: z(r, p) = s00
      p = p - k
      q = q - k

      dp1 = d00: d00 = dm1: dm1 = dm2: dm2 = 0
      sp2 = sp1: sp1 = s00: s00 = sm1: sm1 = 0
      dz = dm1 + d00: dz = 8 * dz + dz:         s00 = s00 - (dz - dm2 - dp1 + 8) \ 16
      sz = s00 + sp1: sz = 8 * sz + sz:         d00 = d00 + (sz - sm1 - sp2 + 8) \ 16
      z(r, q) = d00: z(r, p) = s00

      k = k \ 2
      m = m + m                       'next level
    Loop
    r = r - 1
  Loop

End Sub

'===============================================================================================================
'===============================================================================================================
' ENCODING with the Set Partitioning In Hierarchical Trees Algorithm (Said and Pearlman),
' using the No List SPIHT method by Wheeler and Pearlman (2000 or so)
' This encoding method is in essence the coding decision tree of passing through decreasing values
' of (pyramidically structured) transform coefficients. It is arbitrarily stoppable at any nr of bytes down
' the tree. Its progressively refining. Zero coefficients are never output
'
' use SPIHT on the Web as a search to get the documentation (lots of .pdfs) on this method,
' then think about it for a week or so. :-)
'
' This method is extremely cunning and nearly impenetrable. Its applicable to any structured dataset
'
' It fundamentally rests on the theorem that:
'
' "If the execution path of any algorithm is defined by the results on its branching points,
'  and if the encoder and decoder have the same (sorting) algorithm then the decoder can recover
'  the ordering information easily"  - easier said than done...
'===============================================================================================================

Private Function Encode(z() As Integer, ByVal MinP As Long, ByVal MinQ As Long) As Boolean

 Dim bb As Long, ndc As Long, d As Boolean, s As Long, w As Long
 Dim m As Long, n As Long, pq As Long, p As Long, q As Long, i As Long, j As Long, k As Long
 Dim Blocks() As XBlock, skip() As Long, isskip() As Long

 'INITIALISE

  Call InitSkip(skip(), isskip())

  m = UBound(z, 1) + 1: p = m \ MinP
  n = UBound(z, 2) + 1: q = n \ MinQ

  zCWIHdr.nRC = p
  pq = p * q
  bb = MinP * MinQ                       'This many blocks
  '  w = OptimalGCVThreshold(z())

  ReDim zCoeffs(0 To m * n - 1)
  CPtr = 0

  'Set up ENCODING BLOCKS
  ReDim Blocks(0 To bb - 1)              'setup XBlocks for encoding
  w = 0
  For i = 0 To m - 1 Step p
    For j = 0 To n - 1 Step q
      With Blocks(w)
        ReDim .val(0 To pq - 1)          'values
        ReDim .sign(0 To pq - 1)         'signs
        ReDim .mark(0 To pq - 1)         'flags
        ReDim .dmax(0 To pq \ 4 - 1)     'descendents max values
        ReDim .gmax(0 To pq \ 16 - 1)    'grand descendants max values
        For k = 0 To 3
          .mark(0) = MIP
        Next k
        For k = 1 To 3
          .mark(4 * k) = MD
          Call Push(.mark(), 4 * k)
        Next k
      End With
      w = w + 1
    Next j
  Next i

  'FILL BLOCKS from Transformed Image
  Call FillBlocks(z(), Blocks(), MinP, MinQ)
  Erase z()

  If zCWIHdr.Quality <> 100 Then Call Filter(Blocks(), zCWIHdr.Quality)

  'Find Maxima
  s = 0
  For j = 0 To bb - 1                       'over all blocks find the maxima
    With Blocks(j)
      For i = pq \ 4 - 1 To 0 Step -1
        w = 4 * i
        If i < pq \ 16 Then
          .gmax(i) = .dmax(w) Or .dmax(w + 1) Or .dmax(w + 2) Or .dmax(w + 3)
          .dmax(i) = .val(w) Or .val(w + 1) Or .val(w + 2) Or .val(w + 3) Or .gmax(i)
         Else
          .dmax(i) = .val(w) Or .val(w + 1) Or .val(w + 2) Or .val(w + 3)
        End If
        s = s Or .dmax(i)
      Next i
    End With
  Next j

  'Encode Decision Path
  Call InitBitIO
  zCWIHdr.MaxBits = nBits(s)                    'this is the size of largest value in bits
  s = TwoR(zCWIHdr.MaxBits)                     'this is the size of largest value mask

  Do While s > 0
    'INSIGNIFICANT PIXELS
    For j = 0 To bb - 1                         'over all blocks
      With Blocks(j)
        i = 0
        Do While i < pq                         'start IP Pass
          If .mark(i) = MIP Then                'insignificant pixel
            d = ((.val(i) And s) <> 0)          'set sig bit
            Call OutBit(d)                      'send bit
            If d Then
              Call OutBit(.sign(i) <> 0)        'send sign
              .mark(i) = MNP                    'now newly significant
            End If
            i = i + 1                           'next pixel
           Else
            i = i + skip(.mark(i))              'move past set/block
          End If
        Loop
      End With
    Next j

    'INSIGNIFICANT SET PASS
    For j = 0 To bb - 1
      With Blocks(j)
        i = 0
        Do While i < pq                         'start pass
          If .mark(i) = MD Then                 'a set of descendants
            d = ((.dmax(i \ 4) And s) <> 0)     'set sig bit
            Call OutBit(d)                      'send bit
            If d Then
              .mark(i) = MCP
              .mark(i + 1) = MCP
              .mark(i + 2) = MCP
              .mark(i + 3) = MCP                '4 children to be tested next
              If 4 * i < pq Then
                .mark(4 * i) = MG               'and descendants
              End If
              'no increment to test these next
             Else
              i = i + 4                         'move past siblings
            End If

           ElseIf .mark(i) = MG Then            'a set of grand-descendants
            d = ((.gmax(i \ 16) And s) <> 0)    'set sig bit
            Call OutBit(d)                      'send bit
            If d Then
              .mark(i) = MD
              .mark(i + 4) = MD                 'split into 4 sets
              .mark(i + 8) = MD
              .mark(i + 12) = MD                'test these next
              Call Push(.mark(), i)             'mark the borders
              Call Push(.mark(), i + 4)
              Call Push(.mark(), i + 8)
              Call Push(.mark(), i + 12)
              'no increment to test these next
             Else
              i = i + 16
            End If

           ElseIf .mark(i) = MCP Then
            d = ((.val(i) And s) <> 0)          'set sig bit
            Call OutBit(d)                      'output bit
            If d Then
              Call OutBit(.sign(i) <> 0)        'output sign
              .mark(i) = MNP                    'newly significant
             Else
              .mark(i) = MIP                    'not significant
            End If
            i = i + 1                           'next pixel
           Else
            i = i + isskip(.mark(i))
          End If
        Loop
      End With
    Next j

    'REFINEMENT PASS
    For j = 0 To bb - 1
      With Blocks(j)
        i = 0
        Do While i < pq                         'start pass
          If .mark(i) = MSP Then
            Call OutBit((.val(i) And s) \ s)    'output high bit
            i = i + 1
           ElseIf .mark(i) = MNP Then           'was new now significant
            .mark(i) = MSP
            i = i + 1
           Else
            i = i + skip(.mark(i))              'skip set
          End If
        Loop
      End With
    Next j
    s = s \ 2     'next layer
  Loop

  Call EndBitIO   'finalise Coefficient Bits
  Encode = True

End Function

'The Coefficients are loaded, and Image(), MinP and MinQ are all updated
Private Function Decode(z() As Integer, ByRef MinP As Long, ByRef MinQ As Long) As Boolean

 Dim bb As Long, ndc As Long, d As Boolean, s As Long, w As Long
 Dim m As Long, n As Long, pq As Long, p As Long, q As Long, i As Long, j As Long, k As Long
 Dim Blocks() As XBlock, skip() As Long, isskip() As Long

 'INITIALISE

  Call InitSkip(skip(), isskip())

  With zCWIHdr
    p = .nRC
    q = .nRC
    m = (.Height + 7) And &HFFFFFFF8
    n = (.Width + 7) And &HFFFFFFF8
    If (.flags And CWI_GREYSCALE) <> CWI_GREYSCALE Then n = n * 3
  End With

  MinP = m \ p
  MinQ = n \ q
  pq = p * q
  bb = MinP * MinQ                            'This many blocks

  'Set up ENCODING BLOCKS
  ReDim Blocks(0 To bb - 1)                   'setup XBlocks for encoding
  w = 0
  For i = 0 To m - 1 Step p
    For j = 0 To n - 1 Step q
      With Blocks(w)
        ReDim .val(0 To pq - 1)          'values
        ReDim .sign(0 To pq - 1)         'signs
        ReDim .mark(0 To pq - 1)         'flags
        For k = 0 To 3
          .mark(0) = MIP
        Next k
        For k = 1 To 3
          .mark(4 * k) = MD
          Call Push(.mark(), 4 * k)
        Next k
      End With
      w = w + 1
    Next j
  Next i

  'Decode Decision Path
  Call InitBitIO
  s = TwoR(zCWIHdr.MaxBits)                   'this is the size of largest value mask
  Do While s > 0
    'INSIGNIFICANT PIXELS
    For j = 0 To bb - 1                       'over all blocks
      With Blocks(j)
        i = 0
        Do While i < pq                       'start IP Pass
          If .mark(i) = MIP Then              'insignificant pixel
            If InBit() Then                   'get sig bit
              .val(i) = .val(i) Or (s Or s \ 2)
              .sign(i) = InBit()              'get sign
              .mark(i) = MNP                  'now newly significant
            End If
            i = i + 1                         'next pixel
           Else
            i = i + skip(.mark(i))            'move past set/block
          End If
        Loop
      End With
    Next j

    'INSIGNIFICANT SET PASS
    For j = 0 To bb - 1
      With Blocks(j)
        i = 0
        Do While i < pq                       'start pass
          If .mark(i) = MD Then               'a set of descendants
            If InBit() Then                   'get sigbit
              .mark(i) = MCP
              .mark(i + 1) = MCP
              .mark(i + 2) = MCP
              .mark(i + 3) = MCP              '4 children to be tested next
              If 4 * i < pq Then
                .mark(4 * i) = MG             'and descendants
              End If
              'no increment to test these next
             Else
              i = i + 4                       'move past siblings
            End If

           ElseIf .mark(i) = MG Then          'a set of grand-descendants
            If InBit() Then                   'get sigbit
              .mark(i) = MD
              .mark(i + 4) = MD               'split into 4 sets
              .mark(i + 8) = MD
              .mark(i + 12) = MD              'test these next
              Call Push(.mark(), i)           'mark the borders
              Call Push(.mark(), i + 4)
              Call Push(.mark(), i + 8)
              Call Push(.mark(), i + 12)
              'no increment to test these next
             Else
              i = i + 16
            End If

           ElseIf .mark(i) = MCP Then
            If InBit() Then                     'get sig bit
              .val(i) = .val(i) Or (s Or s \ 2) 'assume middle value
              .sign(i) = InBit()                'get sign
              .mark(i) = MNP                    'newly significant
             Else
              .mark(i) = MIP                    'not significant
            End If
            i = i + 1                           'next pixel
           Else
            i = i + isskip(.mark(i))
          End If
        Loop
      End With
    Next j

    'REFINEMENT PASS
    For j = 0 To bb - 1
      With Blocks(j)
        i = 0
        Do While i < pq                       'start pass
          If .mark(i) = MSP Then
            If InBit() Then                   'get high bit
              .val(i) = .val(i) Or s
             Else
              .val(i) = .val(i) And Not s
            End If
            i = i + 1
           ElseIf .mark(i) = MNP Then         'was new now significant
            .mark(i) = MSP
            i = i + 1
           Else
            i = i + skip(.mark(i))            'skip set
          End If
        Loop
      End With
    Next j
    s = s \ 2     'next layer
  Loop

  'FILL a new Transformed Image from BLOCKS
  ReDim z(0 To m - 1, 0 To n - 1)
  Call EmptyBlocks(z(), Blocks(), MinP, MinQ)
  Decode = True

End Function

'============================== LOW LEVEL ROUTINES ==============================================================

Private Sub InitSkip(ByRef skip() As Long, ByRef isskip() As Long)

  ReDim skip(0 To 15)
  skip(MIP) = 1             'insignificant or untested
  skip(MNP) = 1             'newly significant
  skip(MSP) = 1             'significant
  skip(MCP) = 1             'like MIP but used during IS Pass
  skip(MD) = 4              'first child in a descendant group
  skip(MG) = 16             'first grandchild
  skip(MN2) = 16            '1st grand child set of MD
  skip(MN3) = 64            '2nd grand child set
  skip(MN4) = 256           '3rd grand child
  skip(MN5) = 1024          '4th
  skip(MN6) = 4096          '5th
  skip(MN7) = 16384         '6th
  skip(MN8) = 65536         '7th

  ReDim isskip(0 To 15) As Long
  isskip() = skip()
  isskip(MIP) = 4           'insignificant or untested
  isskip(MNP) = 4           'newly significant
  isskip(MSP) = 4           'significant

End Sub

'The object here is to successively trim values out of the Transform, in such a way to get a graduated loss
'of quality - We will encode all remaining coefficients
'Quality 100 is lossless so we are never called for that
'Quality 0 will remove all coefficients below 100 in the detail block, 43 in the mid block, and 1 in the means
'block. We try to remove values from the detail blocks in preference to the means blocks because means blocks
'leave the essence of the image intact for the longest time.
Private Sub Filter(ByRef Blocks() As XBlock, ByVal Quality As Long)

 Dim i As Long, j As Long, m As Long, n As Long, q As Long
 Dim qa As Long, qb As Long, qc As Long

  If Quality = 100 Then Exit Sub            'lets avoid a lot of sensless compares
  n = UBound(Blocks(0).val) + 1             'the size of the block array
  qc = 100 - Quality
  qb = (10 * qc) \ 23       '/(ln 10)       'entirely arbitrary but gives good quality for size
  qa = (10 * qc) \ 53       '/(ln 10)^2

  For j = UBound(Blocks) To 0 Step -1
    With Blocks(j)
      For i = 0 To n \ 4 - 1                'Means
        If .val(i) < qa Then .val(i) = 0
      Next i

      For i = n \ 4 To 3 * n \ 4 - 1        'MeanDetails
        If .val(i) < qb Then .val(i) = 0
      Next i

      For i = 3 * n \ 4 To n - 1            'Details
        If .val(i) < qc Then .val(i) = 0
      Next i
    End With
  Next j

End Sub

Private Sub Push(ByRef mark() As Byte, ByVal i As Long)

  On Error GoTo DeliberateBoundsError   'DONT TURN OFF BOUNDS CHECKING AS OPTIMISATION!!! else this will fail

  mark(4 * i) = MN2
  mark(16 * i) = MN3
  mark(64 * i) = MN4
  mark(256 * i) = MN5
  mark(1024 * i) = MN6
  mark(4096 * i) = MN7
  mark(16384 * i) = MN8

DeliberateBoundsError:
  On Error GoTo 0

End Sub

'Addresses in the Val() Array are a bit interleaving of i and j  ie r= ...i5j5.i4j4.i3j3.i2j2.i1j1.i0j0
'in this way adresses advance as below, making the val addressing linear and hence easier and faster
'
'Canonical Form (8x8 Block)
'   j=0--1-+-2--3-+--4--5---6--7-+--8--9
'i=0| 0  1 | 4  5 | 16 17  20 21 | 64 65
'  1| 2  3 | 6  7 | 18 19  22 23 | 66 67 etc
'   +------+------+              |
'  2| 8  9 |12 13 | 24 25  28 29 |
'  3|10 11 |14 15 | 26 27  30 31 |
'   +------+------+              |
'  4|32 33  36 37   48 49  52 53 |
'  5|34 35  38 39   50 51  54 55 |
'
'  6|40 41  44 45   56 57  60 61 |
'  7|42 43  46 47   58 59  62 63 |
'   +----------------------------+

'Transform Form (which transform coeffs are equivalent to above
'   j=-0---1---2---3---4---5---6---7--+
'i=0| 0,0 0,4 0,2 0,6 0,1 0,3 0,5 0,7 |
'  1| 4,0 4,4 4,2 2,6 4,1 4,3 4,5 4,7 |
'  2| 2,0 2,4 2,2 2,6 2,1 2,3 2,5 2,7 |
'  3| 6,0 6,4 6,2 6,6 6,1 6,3 6,5 6,7 |
'  4| 1,0 1,4 1,2 1,6 1,1 1,3 1,5 1,7 |
'  5| 3,0 3,4 3,2 3,6 3,1 3,3 3,5 3,7 |
'  6| 5,0 5,4 5,2 5,6 5,1 5,3 5,5 5,7 |
'  7| 7,0 7,4 7,2 7,6 7,1 7,3 7,5 7,7 |
'   +---------------------------------+

'Called ONCE only per Encode/Decode
Private Sub BuildRCIndex(ByRef RCi() As Long, ByRef iRCi() As InvRC, ByVal nRC As Long)

 Dim i As Long, j As Long, v As Long, u As Long, rc As Long, vk As Long, uk As Long, z() As InvRC

  ReDim RCi(0 To nRC - 1, 0 To nRC - 1), iRCi(0 To nRC * nRC - 1), z(0 To nRC - 1, 0 To nRC - 1)

  'Since the Transform is not a canonical form for wavelet transforms, we need a shuffling before assigning
  'indices to the linear array. z() contains the Transform i,j pairs corresponding to the canonical form
  'ie. Canonical (i,j)=(z(i, j).i, z(i, j).j)

  For i = 0 To nRC - 1
    For j = 0 To nRC - 1
      z(i, j).i = i: z(i, j).j = j
    Next j
  Next i
  Call RCShuffle(z(), nRC)        'z(i,j) have now moved to the canonical positions

  'Now we cut out the middleman, by encoding all of the transform coords directly by bit interleaving
  For i = 0 To nRC - 1
    For j = 0 To nRC - 1
      v = TwoR(nBits(i)): vk = 2 * v * v
      u = TwoR(nBits(j)): uk = u * u
      rc = 0
      Do While u > 0 Or v > 0
        If (i And v) <> 0 Then rc = (rc Or vk)
        If (j And u) <> 0 Then rc = (rc Or uk)
        v = v \ 2
        u = u \ 2
        vk = vk \ 4
        uk = uk \ 4
      Loop
      RCi(z(i, j).i, z(i, j).j) = rc      'Forward Index
      iRCi(rc) = z(i, j)                  'Inverse Index
    Next j
  Next i

End Sub

'============================== RCSHUFFLE ====================================================================
'We need to shuffle the transform forward to the canonical form needed to encode it
'The table below show the selections that need to be made to effect this shuffle (in two dimensions)
'For some reason this had my brain in knots for ages...
'
'       0 k/2[k] k/4[k\2] k\8[k\4]    k\16[k\8]                k\32[\16]                                   k\64[k\32]
'k=64 sel 0 -32 -16,48 - 8,24,40,56 - 4,12,20,28,36,44,52,60 - 2,6,10,14,18,                         ..62, -1,3,5,7
'k=32 sel 0 -16 - 8,24 - 4,12,20,28 - 2,6,10,14,18,22,26,30  - 1,3,5,7,9,11,13,15,17,19,21,23,25,27,29,31
'k=16 sel 0 - 8 - 4,12 - 2, 6,10,14 - 1,3, 5, 7, 9,11,13,15
'k=8  sel 0 - 4 - 2, 6 - 1, 3, 5, 7
'k=4  sel 0 - 2 - 1, 3

Private Sub RCShuffle(ByRef z() As InvRC, ByVal nRC As Long)

 Dim t() As InvRC, r As Long, x As Long, y As Long, xt As Long, yt As Long

  ReDim t(0 To nRC - 1, 0 To nRC - 1)       'temp block for shuffle nRC*nRC elements

  xt = 0                                    'select rows from z() to t()
  For x = 0 To nRC - 1                      '(0,x)
    t(0, xt) = z(0, x)
    xt = xt + 1
  Next x

  r = nRC: yt = 1
  Do While r > 1
    y = r \ 2                               'k\2[k]
    Do While y < nRC
      xt = 0
      For x = 0 To nRC - 1
        t(yt, xt) = z(y, x)
        xt = xt + 1
      Next x
      yt = yt + 1
      y = y + r
    Loop
    r = r \ 2
  Loop

  yt = 0                                    'select columns from t() back to z()
  For y = 0 To nRC - 1                      '(y,0)
    z(y, 0) = t(yt, 0)
    yt = yt + 1
  Next y

  r = nRC: x = 1
  Do While r > 1
    xt = r \ 2                              '0, k\2[k]
    Do While xt < nRC
      yt = 0
      For y = 0 To nRC - 1
        z(y, x) = t(yt, xt)
        yt = yt + 1
      Next y
      xt = xt + r
      x = x + 1
    Loop
    r = r \ 2
  Loop

End Sub

'-----------------------------------------------------------------------------------------------------------------
'Debugging
Private Sub DumpImage(ByRef Image() As Integer, ByRef FilePath As String)

 Dim p As Long, q As Long

  Open FilePath For Output As #1
  For p = 0 To UBound(Image, 1)
    For q = 0 To UBound(Image, 2)
      Print #1, Image(p, q); ",";
    Next q
    Print #1,
  Next p
  Close #1

End Sub

'============================ B I T  I/O =========================================================================
Private Sub InitBitIO()

  CPtr = 0
  BitMask = 128

End Sub

Private Function InBit() As Boolean

  InBit = ((zCoeffs(CPtr) And BitMask) <> 0)
  BitMask = BitMask \ 2
  If BitMask = 0 Then
    CPtr = CPtr + 1
    BitMask = 128
  End If

End Function

Private Sub OutBit(ByVal v As Boolean)

  If v Then
    zCoeffs(CPtr) = zCoeffs(CPtr) Or BitMask
   Else
    zCoeffs(CPtr) = zCoeffs(CPtr) And Not BitMask
  End If
  BitMask = BitMask \ 2
  If BitMask = 0 Then
    CPtr = CPtr + 1
    BitMask = 128
  End If

End Sub

Private Sub EndBitIO()

  If BitMask <> 128 Then CPtr = CPtr + 1
  ReDim Preserve zCoeffs(0 To CPtr)

End Sub

'============================ Image <> XBlocks =================================================================

Private Sub FillBlocks(ByRef z() As Integer, ByRef Blocks() As XBlock, ByVal MinP As Long, MinQ As Long)

 Dim p As Long, q As Long, r As Long, n As Long, m As Long, i As Long, j As Long, u As Long, v As Long
 Dim RCi() As Long, iRCi() As InvRC, pq As Long, w As Long

  m = UBound(z, 1) + 1: p = m \ MinP
  n = UBound(z, 2) + 1: q = n \ MinQ

  Call BuildRCIndex(RCi(), iRCi(), p)

  w = 0
  For v = 0 To m - 1 Step p              'for every fundamental block
    For u = 0 To n - 1 Step q
      With Blocks(w)
        For i = 0 To p - 1
          For j = 0 To q - 1
            r = RCi(i, j)
            .val(r) = Abs(z(v + i, u + j))
            .sign(r) = (z(v + i, u + j) < 0) And 1       'negative=1
          Next j
        Next i
      End With
      w = w + 1
    Next u
  Next v

  'we now have blocks of p*q values in correct serial order for encoding, z() is eraseable now

End Sub

Private Sub EmptyBlocks(ByRef z() As Integer, ByRef Blocks() As XBlock, ByVal MinP As Long, MinQ As Long)

 Dim p As Long, q As Long, r As Long, n As Long, m As Long, i As Long, j As Long, u As Long, v As Long
 Dim RCi() As Long, iRCi() As InvRC, pq As Long, w As Long, k As Long

  m = UBound(z, 1) + 1: p = m \ MinP
  n = UBound(z, 2) + 1: q = n \ MinQ

  Call BuildRCIndex(RCi(), iRCi(), p)

  w = 0: pq = p * q
  For v = 0 To m - 1 Step p              'for every fundamental block
    For u = 0 To n - 1 Step q
      With Blocks(w)
        For k = 0 To pq - 1
          i = iRCi(k).i
          j = iRCi(k).j
          If .sign(k) <> 0 Then
            z(v + i, u + j) = -.val(k)
           Else
            z(v + i, u + j) = .val(k)
          End If
        Next k
      End With
      w = w + 1
    Next u
  Next v

  'we now have rebuilt the image z() ready for shuffling and transforming, Blocks() is eraseable now

End Sub

'------------------------------ hDC <> Image -------------------------------------------------------------------

Private Function hDCtoImage(ByRef Image() As Integer, ByVal hDC As Long) As Boolean  'get Image() from hDC =TRUE is Good

 'Given a valid hDC generate an Image() for later encoding. All three components are included at once as separate
 'values either as RGB or YCbCr. A DIBSection is temporarily created to hold bytes of the Image

 Dim SA         As SAFEARRAY
 Dim BI         As BITMAPINFO 'Type containing the Bitmap information
 Dim hDIb       As Long       'Handle to the DIBSection
 Dim hBmpOld    As Long       'Handle to the old bitmap in the DC, for clear up
 Dim MemhDC     As Long       'Handle to the Device context holding the DIBSection
 Dim lPtr       As Long       'Address of memory pointing to the DIBSection's bits

 Dim Pixel()    As Byte       'Byte array containing pixel data
 Dim RowMod     As Long       'Width of A Row in Bytes

 Dim Width      As Long       'Sample width
 Dim Height     As Long       'Sample height

 Dim i          As Long       'row ptr
 Dim p          As Long       'pixel ptr
 Dim q          As Long       'ptr to Image byte
 Dim n          As Long       'n bytes in image

  With zCWIHdr

    hBmpOld = GetCurrentObject(hDC, OBJ_BITMAP)                 'What does the current bitmap look like?
    If GetObject(hBmpOld, LenB(BI.bmiHeader), BI) <> 0 Then     'get its statistics
      .Width = BI.bmiHeader.biWidth
      .Height = Abs(BI.bmiHeader.biHeight)

      MemhDC = CreateCompatibleDC(0)                            'set about making a clone of it
      If MemhDC <> 0 Then

        Width = (.Width + 7) And &HFFFFFFF8                     '8 byte modulo
        Height = (.Height + 7) And &HFFFFFFF8
        RowMod = (((Width * 24) + 31&) And Not 31&) \ 8&

        With BI.bmiHeader
          .biSize = LenB(BI.bmiHeader)
          .biWidth = Width
          .biHeight = -Height                         'top to bottom please
          .biPlanes = 1
          .biBitCount = 24
          .biCompression = BI_RGB
          .biSizeImage = RowMod * Height              '4 byte barrier
        End With

        hDIb = CreateDIBSection2(MemhDC, BI, DIB_RGB_COLORS, lPtr, 0, 0)
        If hDIb <> 0 Then
          With SA                                     'This code copies the pointer of the 2-D bitmap
            .cbElements = 1                           'pixel data to the pointer of the 1D Pixel() array.
            .cDims = 1                                'This allows you to read/modify the pixel data
            .Bounds(0).lLbound = 0                    'as if it were stored in the Pixel() array.
            .Bounds(0).cElements = RowMod * Height
            .pvData = lPtr                            'Note that this is extreamly efficient, since it copies
          End With                                    'a pointer to the data, and not the data itself.
          hBmpOld = SelectObject(MemhDC, hDIb)        'Select DIBSection into DC

          If (0 <> BitBlt(MemhDC, 0, 0, Width, Height, hDC, 0, 0, vbSrcCopy)) Then

            CopyMemory ByVal VarPtrArray(Pixel), VarPtr(SA), 4& 'Get Pixel array descriptor

            'get all of the salient bits we need
            i = 0
            p = 0
            q = 0
            n = Height * RowMod

            If (.flags And CWI_GREYSCALE) = CWI_GREYSCALE Then
              ReDim Image(0 To Height - 1, 0 To Width - 1)
              Do While p < n
                Image(i, q) = (19595& * Pixel(p + 2) + 38470 * Pixel(p + 1) + 7471& * Pixel(p)) \ 65536 - 128 'Y
                q = q + 1
                p = p + 3
                If q = Width Then                      'at end of a row
                  q = 0
                  i = i + 1                            'next dest   row
                  p = p + RowMod - Width * 3           'next source row
                End If
              Loop
             Else
              ReDim Image(0 To Height - 1, 0 To 3 * Width - 1)
              Do While p < n
                If (.flags And CWI_YCbCr) <> 0 Then    'we need to do YCbCr Conversion
                  'RGB to YCbCr Conversion
                  'YCbCr (256 levels) can be computed directly from 8-bit RGB as follows:
                  '   Y =     0.299 R + 0.587  G + 0.114  B
                  '   Cb = - 0.1687 R - 0.3313 G + 0.5    B + 128
                  '   Cr =      0.5 R - 0.4187 G - 0.0813 B + 128
                  Image(i, q) = (19595& * Pixel(p + 2) + 38470 * Pixel(p + 1) + 7471& * Pixel(p)) \ 65536 - 128 'Y
                  Image(i, q + 1) = (-11059& * Pixel(p + 2) - 21709& * Pixel(p + 1) + 32768 * Pixel(p)) \ 65536 'Cb
                  Image(i, q + 2) = (32768 * Pixel(p + 2) - 27439& * Pixel(p + 1) - 5329& * Pixel(p)) \ 65536   'Cr
                 Else                                   'straight RGB
                  Image(i, q) = Pixel(p + 2) - 128
                  Image(i, q + 1) = Pixel(p + 1) - 128
                  Image(i, q + 2) = Pixel(p) - 128
                End If

                q = q + 3         'adv ptrs
                p = p + 3         'skip pixels

                If q = 3 * Width Then                 'at end of a row
                  q = 0
                  i = i + 1                           'next dest   row
                  p = p + RowMod - Width * 3          'next source row
                End If
              Loop
            End If
            hDCtoImage = True
            CopyMemory ByVal VarPtrArray(Pixel), 0&, 4 'Clear the Pixel array descriptor
          End If
          Call SelectObject(hDC, hBmpOld)             'Select CompatibleDC  (unselect DIBSection)
          Call DeleteObject(hDIb)                     'Delete DIBSection
        End If
        Call DeleteObject(MemhDC)                     'Delete CompatibleDC
      End If
    End If
  End With

End Function

Private Function ImagetoDIB(ByRef Image() As Integer) As Long  'make DIB from Image()

 'Given a valid hDC generate an Image() for later encoding. All three components are included at once as separate
 'values either as RGB or YCbCr. A DIBSection is temporarily created to hold bytes of the Image

 Dim SA         As SAFEARRAY
 Dim BI         As BITMAPINFO 'Type containing the Bitmap information
 Dim MemhDC     As Long       'Handle to the Device context holding the DIBSection
 Dim hDIb       As Long       'Handle to the DIB with the new MemDC
 Dim lPtr       As Long       'Address of memory pointing to the DIBSection's bits

 Dim Pixel()    As Byte       'Byte array containing pixel data
 Dim RowMod     As Long       'Width of A Row in Bytes

 Dim Width      As Long       'Sample width
 Dim Height     As Long       'Sample height

 Dim i          As Long       'row ptr
 Dim p          As Long       'pixel ptr
 Dim q          As Long       'ptr to Image Data
 Dim n          As Long       'n bytes in image

  With zCWIHdr

    MemhDC = CreateCompatibleDC(0)                            'set about making a DIB
    If MemhDC <> 0 Then

      RowMod = (((.Width * 24) + 31&) And Not 31&) \ 8&

      With BI.bmiHeader
        .biSize = LenB(BI.bmiHeader)
        .biWidth = zCWIHdr.Width
        .biHeight = -zCWIHdr.Height                       'top to bottom please
        .biPlanes = 1
        .biBitCount = 24
        .biCompression = BI_RGB
        .biSizeImage = RowMod * zCWIHdr.Height            '4 byte barrier
      End With

      hDIb = CreateDIBSection2(MemhDC, BI, DIB_RGB_COLORS, lPtr, 0, 0)
      If hDIb <> 0 Then
        With SA                                           'This code copies the pointer of the 2-D bitmap
          .cbElements = 1                                 'pixel data to the pointer of the 1D Pixel() array.
          .cDims = 1                                      'This allows you to read/modify the pixel data
          .Bounds(0).lLbound = 0                          'as if it were stored in the Pixel() array.
          .Bounds(0).cElements = RowMod * zCWIHdr.Height
          .pvData = lPtr                                  'Note that this is extremely efficient, since it copies
        End With                                          'a pointer to the data, and not the data itself.

        CopyMemory ByVal VarPtrArray(Pixel), VarPtr(SA), 4& 'Get Pixel array descriptor

        'get all of the salient bits we need
        i = 0
        p = 0
        q = 0
        n = zCWIHdr.Height * RowMod

        If (.flags And CWI_GREYSCALE) = CWI_GREYSCALE Then
          Do While p < n
            Pixel(p + 2) = Clamp(128 + Image(i, q))  'R
            Pixel(p + 1) = Pixel(p + 2)                    'g=r
            Pixel(p) = Pixel(p + 2)                        'b=r

            p = p + 3         'skip pixels
            q = q + 1         'adv ptrs
            If q = .Width Then                     'at end of a row
              q = 0
              i = i + 1                           'next dest   row
              p = i * RowMod                      'next source row
            End If
          Loop
         Else
          Do While p < n
            If (.flags And CWI_YCbCr) <> 0 Then    'we need to do YCbCr Conversion
              'YCbCr to RGB Conversion
              'RGB can be computed directly from YCbCr (256 levels) as follows:
              '   R = Y                      + 1.402 (Cr-128)
              '   G = Y - 0.34414 (Cb-128) - 0.71414 (Cr-128)
              '   B = Y + 1.772   (Cb-128)
              Pixel(p + 2) = Clamp(128 + Image(i, q) + (1402& * Image(i, q + 2)) \ 1000&) 'R
              Pixel(p + 1) = Clamp(128 + Image(i, q) _
                    - (34414 * Image(i, q + 1)) \ 100000 _
                    - (71414 * Image(i, q + 2)) \ 100000)                     'G
              Pixel(p) = Clamp(128 + Image(i, q) + (1772& * Image(i, q + 1)) \ 1000&)    'B
             Else                                                                                'straight RGB
              Pixel(p + 2) = Clamp(128 + Image(i, q))
              Pixel(p + 1) = Clamp(128 + Image(i, q + 1))
              Pixel(p) = Clamp(128 + Image(i, q + 2))
            End If

            p = p + 3         'skip pixels
            q = q + 3         'adv ptrs

            If q = 3 * .Width Then                  'at end of a row
              q = 0
              i = i + 1                             'next dest   row
              p = i * RowMod                        'next source row
            End If
          Loop
        End If

        CopyMemory ByVal VarPtrArray(Pixel), 0&, 4  'Clear the Pixel array descriptor
        ImagetoDIB = hDIb
      End If
      Call DeleteObject(MemhDC)                     'Delete CompatibleDC
    End If
  End With

End Function

'Make sure no value is too large or too small
Private Function Clamp(ByVal v As Long) As Long

  If v < 0 Then
    v = 0
   ElseIf v > 255 Then
    v = 255
  End If
  Clamp = v

End Function

'=====================  SAVE AND LOAD === PUBLIC FUNCTIONS ====================================================

Public Function SaveCWI(ByVal FilePath As String, _
                        ByVal hDC As Long, _
                        Optional ByVal Quality As Long = 75, _
                        Optional ByVal flags As CWI_FLAGS = CWI_YCbCr, _
                        Optional ByVal Transform As CWI_TRANSFORM = CWI_T22, _
                        Optional ByVal Comment As String = "") As Boolean

 Dim ff As Long, Image() As Integer, MinP As Long, MinQ As Long

  If Len(FilePath) <> 0 Then
    On Error GoTo NoSave

    With zCWIHdr
      .Tag = &H49574323   '#CWI
      .Version = 1
      .Revision = 1
      .flags = (flags And &HFF)
      If Quality < 1 Or Quality > 100 Then Quality = 75
      .Quality = Quality
      If Transform < CWI_T11 Or Transform > CWI_T44 Then Transform = CWI_T22  '(2,2) transform
      .Transform = Transform
      zComment() = StrConv(Comment & "CWI.cls ©2004 RVT" & Chr$(0), vbFromUnicode)
      .LenComment = UBound(zComment) + 1
    End With

    If hDCtoImage(Image(), hDC) Then             'get Dimensions and make up Image(), CWI Hdr is updated
      'Call DumpImage(Image(), "c:\temp\DumpF1.csv")

      Select Case Transform
       Case CWI_T11: Call Fwd_LWT_11_2D(Image(), MinP, MinQ)
       Case CWI_T22: Call Fwd_LWT_22_2D(Image(), MinP, MinQ)
       Case CWI_T44: Call Fwd_LWT_44_2D(Image(), MinP, MinQ)
      End Select
      'Call DumpImage(Image(), "c:\temp\DumpF2.csv")

      If Encode(Image(), MinP, MinQ) Then         'CWI Hdr is updated
        With zCWIHdr
          .LenCoeffs = UBound(zCoeffs) + 1
          .Size = LenB(zCWIHdr) + .LenCoeffs + .LenComment
        End With
        ff = FreeFile()
        Open FilePath For Binary Access Write As #ff
        Put #ff, , zCWIHdr
        Put #ff, , zCoeffs()
        Put #ff, , zComment()
        Close #ff
      End If
    End If
  End If
  On Error GoTo 0

Exit Function

NoSave:
  Close #ff
  On Error GoTo 0

End Function

'Image is loaded as a StdPicture (Caller Must Dispose)
Public Function LoadCWIasStdPic(ByVal FilePath As String) As StdPicture

 Dim hDIb          As Long
 Dim sp            As StdPicture 'used to Make StdPic
 Dim PicDesc       As PictDesc
 Dim IID_IDispatch As GUID

  hDIb = LoadCWIasDIB(FilePath)
  If hDIb <> 0 Then
    'Returns a StdPicture from the Internal Image  (based on Original Code by Vlad Vissoultchev.)
    '-- Fill image info
    With PicDesc
      .Size = Len(PicDesc)
      .Type = vbPicTypeBitmap
      .hBmp = hDIb
      .hPal = 0
    End With

    '-- Fill GUID info
    With IID_IDispatch
      .Data1 = &H20400
      .Data4(0) = &HC0
      .Data4(7) = &H46
    End With

    '-- Create picture from bitmap handle
    Call OleCreatePictureIndirect(PicDesc, IID_IDispatch, 1, sp)
    Set LoadCWIasStdPic = sp
  End If

End Function

'Image is loaded as a hDIB (Caller Must Dispose)
Public Function LoadCWIasDIB(ByVal FilePath As String) As Long

 Dim ff As Long, Image() As Integer, MinP As Long, MinQ As Long

  If Len(FilePath) <> 0 Then
    On Error GoTo NoLoad
    ff = FreeFile()
    Open FilePath For Binary Access Read As #ff
    Get #ff, , zCWIHdr

    If zCWIHdr.Tag = &H49574323 Then                      '#CWI
      ReDim zCoeffs(0 To zCWIHdr.LenCoeffs - 1)
      Get #ff, , zCoeffs()
      ReDim zComment(0 To zCWIHdr.LenComment - 1)
      Get #ff, , zComment()
      Close #ff

      If Decode(Image(), MinP, MinQ) Then
        ' Call DumpImage(Image(), "c:\temp\DumpI1.csv")

        Select Case zCWIHdr.Transform
         Case CWI_T11: Call Inv_LWT_11_2D(Image(), MinP, MinQ)
         Case CWI_T22: Call Inv_LWT_22_2D(Image(), MinP, MinQ)
         Case CWI_T44: Call Inv_LWT_44_2D(Image(), MinP, MinQ)
        End Select

        ' Call DumpImage(Image(), "c:\temp\DumpI2.csv")

        LoadCWIasDIB = ImagetoDIB(Image())              'make Memory DIB
      End If
    End If
  End If
  On Error GoTo 0

Exit Function

NoLoad:
  Close #ff
  On Error GoTo 0

End Function

'the routine below is functionally equivalent to that below but entirely in integers only
' nBits  = Int((Log(Abs(v))/Log(2)))+1             'v<>0, 0 if v=0
Private Function nBits(ByVal v As Long) As Long    'effectively binary search for Log2 -32768<v<32767

 Const TWOE00  As Long = &H1&
 Const TWOE01  As Long = &H2&
 Const TWOE02  As Long = &H4&
 Const TWOE03  As Long = &H8&
 Const TWOE04  As Long = &H10&
 Const TWOE05  As Long = &H20&
 Const TWOE06  As Long = &H40&
 Const TWOE07  As Long = &H80&
 Const TWOE08  As Long = &H100&
 Const TWOE09  As Long = &H200&
 Const TWOE10  As Long = &H400&
 Const TWOE11  As Long = &H800&
 Const TWOE12  As Long = &H1000&
 Const TWOE13  As Long = &H2000&
 Const TWOE14  As Long = &H4000&
 Const TWOE15  As Long = &H8000&

  If v < 0 Then v = -v

  If v < TWOE08 Then                                    'use linear table lookup for values <256
    nBits = TwoB(v)
   Else                                                 'use binary search
    '    If v < TWOE08 Then                             '0..255 bits 7..0
    '      If v < TWOE04 Then                           '0.. 15 bits 3..0
    '        If v < TWOE02 Then                         '0..  1 bits 1..0
    '          If v < TWOE01 Then
    '            nBits = 1
    '          Else
    '            nBits = 2
    '          End If
    '        ElseIf v < TWOE03 Then                     '4..  7 bits 3..2
    '          nBits = 3
    '        Else
    '          nBits = 4
    '        End If
    '      Else                                         '16..255  bits 7..4
    '        If v < TWOE06 Then                         '16.. 63  bits 5..4
    '          If v < TWOE05 Then
    '            nBits = 5
    '          Else
    '            nBits = 6
    '          End If
    '        ElseIf v < TWOE07 Then                     '64..127 bits 7..6
    '          nBits = 7
    '        Else
    '          nBits = 8
    '        End If
    '      End If
    '    Else                                           '256..32768 bits 15..8
    If v < TWOE12 Then                           'bits 11..8
      If v < TWOE10 Then                         'bits  9..8
        If v < TWOE09 Then
          nBits = 9
         Else
          nBits = 10
        End If
       ElseIf v < TWOE11 Then
        nBits = 11
       Else                                       'bits 11..10
        nBits = 12
      End If
     Else                                         'bits 15..12
      If v < TWOE14 Then                         'bits 13..12
        If v < TWOE13 Then
          nBits = 13
         Else
          nBits = 14
        End If
       ElseIf v < TWOE15 Then                     'bits 15..14
        nBits = 15
       Else
        nBits = 16
      End If
    End If
  End If
  '  End If

End Function

'========================================================================================
'                         C L A S S   I N I T I A L I Z A T I O N
'========================================================================================

Private Sub Class_Initialize()

 Dim i As Long

 'Powers of 2

  Call Init_BitMasks

  'The nr of bits in value
  TwoB(0) = 0: TwoB(1) = 1: TwoB(2) = 2: TwoB(3) = 2
  For i = 4 To 7:     TwoB(i) = 3: Next i
  For i = 8 To 15:    TwoB(i) = 4: Next i
  For i = 16 To 31:   TwoB(i) = 5: Next i
  For i = 32 To 63:   TwoB(i) = 6: Next i
  For i = 64 To 127:  TwoB(i) = 7: Next i
  For i = 128 To 255: TwoB(i) = 8: Next i

End Sub

Private Sub Init_BitMasks()

 Dim i As Long, sb() As Variant

  sb = Array(&H1&, &H2&, &H4&, &H8&, _
       &H10&, &H20&, &H40&, &H80&, _
       &H100&, &H200&, &H400&, &H800&, _
       &H1000&, &H2000&, &H4000, &H8000&, _
       &H10000, &H20000, &H40000, &H80000, _
       &H100000, &H200000, &H400000, &H800000, _
       &H1000000, &H2000000, &H4000000, &H8000000, _
       &H10000000, &H20000000, &H40000000, &H80000000)

  For i = 0 To 30
    TwoP(i) = sb(i)
    TwoR(i + 1) = sb(i)
  Next i
  TwoP(31) = sb(31)

End Sub


':) Ulli's VB Code Formatter V2.16.6 (2004-Jan-01 23:19) 170 + 1885 = 2055 Lines
