object Form1: TForm1
  Left = 0
  Top = 0
  Caption = 'Reorganizar Parametros - Configuracion'
  ClientHeight = 240
  ClientWidth = 625
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 13
  object Label1: TLabel
    Left = 16
    Top = 12
    Width = 159
    Height = 13
    Caption = 'Archivo de mapeo de renombres:'
  end
  object Edit1: TEdit
    Left = 16
    Top = 30
    Width = 500
    Height = 21
    ReadOnly = True
    TabOrder = 0
  end
  object BtnSeleccionarArchivo: TButton
    Left = 522
    Top = 28
    Width = 87
    Height = 23
    Caption = 'Examinar...'
    TabOrder = 1
    OnClick = BtnSeleccionarArchivoClick
  end
  object BtnEjecutar: TButton
    Left = 16
    Top = 80
    Width = 121
    Height = 32
    Caption = 'Ejecutar reorganizacion'
    TabOrder = 2
    OnClick = BtnEjecutarClick
  end
  object BtnDiagnosticar: TButton
    Left = 147
    Top = 80
    Width = 121
    Height = 32
    Caption = 'Diagnosticar renombres'
    TabOrder = 3
    OnClick = BtnDiagnosticarClick
  end
  object BtnListarParametros: TButton
    Left = 278
    Top = 80
    Width = 121
    Height = 32
    Caption = 'Listar parametros'
    TabOrder = 4
    OnClick = BtnListarParametrosClick
  end
  object Label2: TLabel
    Left = 16
    Top = 122
    Width = 128
    Height = 13
    Caption = 'Nombre del parametro:'
  end
  object Label3: TLabel
    Left = 230
    Top = 122
    Width = 89
    Height = 13
    Caption = 'Valor por defecto:'
  end
  object EditParamName: TEdit
    Left = 16
    Top = 140
    Width = 200
    Height = 21
    TabOrder = 5
  end
  object EditParamValue: TEdit
    Left = 230
    Top = 140
    Width = 200
    Height = 21
    TabOrder = 6
  end
  object BtnAgregarParametro: TButton
    Left = 444
    Top = 138
    Width = 165
    Height = 25
    Caption = 'Agregar a todos'
    TabOrder = 7
    OnClick = BtnAgregarParametroClick
  end
  object OpenDialog1: TOpenDialog
    Filter = 'Archivos de texto (*.txt)|*.txt|Todos los archivos (*.*)|*.*'
    Left = 560
    Top = 88
  end
  object SaveDialog1: TSaveDialog
    DefaultExt = 'txt'
    Filter = 'Archivos de texto (*.txt)|*.txt|Todos los archivos (*.*)|*.*'
    Left = 560
    Top = 128
  end
end
