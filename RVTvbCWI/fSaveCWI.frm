VERSION 5.00
Begin VB.Form fSaveCWI 
   BorderStyle     =   1  'Fixed Single
   Caption         =   "CWI Compression Settings"
   ClientHeight    =   2490
   ClientLeft      =   45
   ClientTop       =   330
   ClientWidth     =   4455
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MinButton       =   0   'False
   ScaleHeight     =   2490
   ScaleWidth      =   4455
   StartUpPosition =   1  'CenterOwner
   Begin VB.CommandButton cmdFinish 
      Caption         =   "Cancel"
      Height          =   375
      Index           =   0
      Left            =   120
      TabIndex        =   4
      Top             =   2040
      Width           =   1215
   End
   Begin VB.CommandButton cmdFinish 
      Caption         =   "OK"
      Height          =   375
      Index           =   1
      Left            =   3120
      TabIndex        =   5
      Top             =   2040
      Width           =   1215
   End
   Begin VB.Frame Frame1 
      Height          =   1815
      Left            =   120
      TabIndex        =   6
      Top             =   120
      Width           =   4215
      Begin VB.CheckBox chkRGB 
         Caption         =   "Use RGB"
         Height          =   255
         Left            =   1500
         TabIndex        =   9
         Top             =   1320
         Width           =   1155
      End
      Begin VB.CheckBox chkGreyscale 
         Caption         =   "Greyscale"
         Height          =   255
         Left            =   360
         TabIndex        =   2
         Top             =   1320
         Width           =   1335
      End
      Begin VB.CommandButton cmdComment 
         Caption         =   "Comment"
         Height          =   255
         Left            =   2880
         TabIndex        =   3
         Top             =   1320
         Width           =   1095
      End
      Begin VB.ComboBox cboTransform 
         Height          =   315
         ItemData        =   "fSaveCWI.frx":0000
         Left            =   1920
         List            =   "fSaveCWI.frx":000D
         Style           =   2  'Dropdown List
         TabIndex        =   1
         Top             =   840
         Width           =   2055
      End
      Begin VB.HScrollBar hscQuality 
         Height          =   255
         Left            =   1920
         Max             =   100
         Min             =   1
         TabIndex        =   0
         Top             =   360
         Value           =   1
         Width           =   2055
      End
      Begin VB.Label lblTransform 
         Caption         =   "Transform"
         Height          =   255
         Left            =   360
         TabIndex        =   8
         Top             =   840
         Width           =   1455
      End
      Begin VB.Label lblQuality 
         Caption         =   "Quality:"
         Height          =   255
         Left            =   360
         TabIndex        =   7
         Top             =   360
         Width           =   1215
      End
   End
End
Attribute VB_Name = "fSaveCWI"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False

Option Explicit

Private m_Image     As cImage
Private m_FileName  As String
Private m_Transform As Long
Private m_Quality   As Long
Private m_Flags     As CWI_FLAGS
Private m_Comment   As String

Public Sub SaveImage(TheImage As cImage, FileName As String)

  Set m_Image = TheImage 'Call this before the form loads to initialize it
  m_FileName = FileName

End Sub

Private Sub Form_Load()

  cboTransform.ListIndex = 1  '2,2
  m_Transform = 2
  m_Quality = 75
  m_Flags = CWI_YCbCr
  hscQuality.Value = 75

End Sub

Private Sub cboTransform_Click()

  m_Transform = cboTransform.ListIndex + 1
    
End Sub

Private Sub chkGreyscale_Click()

  If chkGreyscale.Value = 1 Then
    m_Flags = m_Flags Or CWI_GREYSCALE
  Else
    m_Flags = m_Flags And Not CWI_GREYSCALE
  End If

End Sub

Private Sub chkRGB_Click()

  If chkRGB.Value = True Then
    m_Flags = m_Flags And Not CWI_YCbCr
  Else
    m_Flags = m_Flags Or CWI_YCbCr
  End If

End Sub

Private Sub hscQuality_Change()

  m_Quality = hscQuality.Value
  lblQuality.Caption = "Quality: " & CStr(hscQuality.Value)
  
End Sub

Private Sub cmdComment_Click()

 Dim NewComment As New fComment

  NewComment.Comment = m_Comment
  NewComment.Show vbModal, Me
  m_Comment = NewComment.Comment
  Set NewComment = Nothing

End Sub

Private Sub cmdFinish_Click(Index As Integer)

  Dim Timer1 As cTimingPC, CWI As cCWI
  Dim et1 As Long, et2 As Long ', hDIb As DIB
  
  If Index = 1 Then
    Set CWI = New cCWI
    Set Timer1 = New cTimingPC
    
    'Delete file if it exists
    RidFile m_FileName

    'Save the CWI file
    Timer1.Reset
    Call CWI.SaveCWI(m_FileName, m_Image.hDC, m_Quality, m_Flags, m_Transform, m_Comment)
    et1 = 1000 * Timer1.Elapsed
    
    'Load the CWI file
'    Timer1.Reset
'    Call m_CWI.LoadCWI(hDIb, m_FileName)
'    et2 = 1000 * Timer1.Elapsed
    
    MsgBox "ET = " & et1 & vbCrLf & "ET2= " & et2 & vbCrLf & "TOT = " & et1 + et2
    Set CWI = Nothing
    Set Timer1 = Nothing
  End If

  Set m_Image = Nothing
  Unload Me

End Sub

':) Ulli's VB Code Formatter V2.16.6 (2003-Nov-29 23:10) 7 + 81 = 88 Lines
