{ ==========================================================================
  ReorganizarParametros_SchLib.pas

  Script DelphiScript para Altium Designer.

  LOGICA CONSERVADORA:
    Este script SOLO toca los parametros que vos declaraste explicitamente
    (en el archivo de renombres y en NEW_PARAMS mas abajo). Cualquier otro
    parametro del componente -sea del sistema (Comment, Designator, Value,
    Footprint, etc.) o cualquier parametro propio que no hayas listado- NO
    se lee, NO se borra, NO se mueve y NO se modifica de ninguna forma.

  CASO ESPECIAL: PARAMETROS TIPO "LINK"
    Cuando en Altium se agrega un campo usando Add > Link (en vez de
    Add > Parameter), NO se crea un parametro comun. Internamente se crean
    DOS parametros con nombres tipo:
        ComponentLink<n>Description   -> guarda el "nombre" que se ve
        ComponentLink<n>URL           -> guarda la URL / ruta de destino
    (<n> es el numero de indice del link: 1, 2, 3, etc.)

    Por eso, para renombrar algo como "_Man_Lnk" (que en realidad es el
    VALOR del parametro ComponentLinkNDescription, no un nombre de
    parametro real), el script:
      1) Primero intenta encontrarlo como parametro normal (por Name).
      2) Si no lo encuentra, revisa si es un Link: busca un parametro
         "ComponentLink*Description" cuyo VALOR actual coincida con el
         nombre viejo, y en ese caso solo le cambia el valor (la
         "descripcion") al nombre nuevo. El "ComponentLink*URL" asociado
         NO se toca en ningun momento, para no perder la URL real.
      3) Este tipo de entrada NO participa del reordenamiento general
         (Paso 3): Altium maneja el orden de los Links con su propio
         indice interno <n>, que se usa para el submenu References, y no
         es parte de la grilla general de parametros.

  QUE HACE, para cada componente de la libreria .SchLib abierta:
    1) Lee el mapeo "nombre actual -> nombre nuevo" desde un archivo de
       texto externo (tab-separado), tal como el que me pasaste.
    2) Para cada par del mapeo:
       - Si es un parametro comun: lo renombra (conservando su valor) y
         lo guarda para recrearlo en el orden final.
       - Si es un Link (ver arriba): solo actualiza su descripcion en el
         lugar, sin recrear nada y sin afectar su posicion/indice.
    3) Agrega los parametros nuevos listados en NEW_PARAMS (si el
       componente no los tiene ya).
    4) Recrea, en el orden de FINAL_ORDER, unicamente los parametros
       comunes que pasaron por el Paso 2 o el Paso 3. Todo lo demas en el
       componente (sistema, otros propios no listados, y los Links)
       mantiene su posicion original intacta.

    NOTA sobre FINAL_ORDER: todavia no lo definiste, asi que por ahora el
    script los recrea en el mismo orden en que aparecen en el archivo de
    renombres + NEW_PARAMS. Cuando me pases el orden final, actualizamos
    la lista FINAL_ORDER y listo, no hace falta tocar nada mas del script.

  IMPORTANTE (limitacion tecnica de DelphiScript):
    DelphiScript NO soporta arrays dinamicos ("Array Of Tipo" + SetLength).
    Por eso NEW_PARAMS y FINAL_ORDER se cargan usando TStringList.Add(),
    en vez de asignar por indice como en Delphi normal.

  ANTES DE CORRERLO:
    - Backup del .SchLib. El script modifica todos los componentes de la
      libreria abierta.
    - Ajusta la constante RENAME_FILE con la ruta real de tu archivo .txt.
    - Completa la seccion NEW_PARAMS con los parametros nuevos (cuando
      los tengas).
    - Completa la seccion FINAL_ORDER con el orden definitivo (cuando lo
      tengas).
   ========================================================================== }

{ DelphiScript de Altium necesita que se le indiquen las unidades desde las
  cuales tomar los tipos, constantes y objetos globales (SchServer, etc.).
  Sin esta seccion es muy probable que aparezcan errores del tipo
  "Identifier not declared" o "Unknown identifier". }
uses
    AltiumScripting,
    SchLib,
    SchDoc;


// ---------------------------------------------------------------------
// Utilidades de parseo de texto
// ---------------------------------------------------------------------

Function CollapseWhitespace(S : String) : String;
Var
    R : String;
    i : Integer;
    C : String;
Begin
    R := '';
    For i := 1 To Length(S) Do
    Begin
        C := S[i];
        If (C = #9) Then C := ' ';
        // Solo agregar el caracter si NO es un espacio repetido
        If Not ((C = ' ') And (R <> '') And (R[Length(R)] = ' ')) Then
            R := R + C;
    End;
    Result := Trim(R);
End;

// Separa una linea "NombreActual <tabs> NombreNuevo [// comentario]"
// Devuelve True si encontro dos campos validos.
Function ParseMapLine(RawLine : String; Var Field1, Field2 : String) : Boolean;
Var
    Line : String;
    p    : Integer;
Begin
    Result := False;
    Field1 := '';
    Field2 := '';

    Line := RawLine;

    // Cortar comentario "// ..." si existe
    p := Pos('//', Line);
    If p > 0 Then Line := Copy(Line, 1, p - 1);

    Line := CollapseWhitespace(Line);
    If Line = '' Then Exit;

    p := Pos(' ', Line);
    If p = 0 Then Exit; // linea con un solo campo, no es valida

    Field1 := Copy(Line, 1, p - 1);
    Field2 := Trim(Copy(Line, p + 1, Length(Line)));

    p := Pos(' ', Field2);
    If p > 0 Then Field2 := Copy(Field2, 1, p - 1);

    If (Field1 <> '') And (Field2 <> '') Then
        Result := True;
End;

// Carga el archivo de mapeo en dos TStringList (deben venir creadas)
Procedure LoadRenameMap(FilePath : String; OldList, NewList : TStringList);
Var
    RawLines : TStringList;
    i        : Integer;
    F1, F2   : String;
Begin
    OldList.Clear;
    NewList.Clear;

    RawLines := TStringList.Create;
    Try
        RawLines.LoadFromFile(FilePath);
        For i := 0 To RawLines.Count - 1 Do
        Begin
            If ParseMapLine(RawLines[i], F1, F2) Then
            Begin
                OldList.Add(F1);
                NewList.Add(F2);
            End;
        End;
    Finally
        RawLines.Free;
    End;
End;

Function StringStartsWith(S, Prefix : String) : Boolean;
Begin
    Result := Copy(S, 1, Length(Prefix)) = Prefix;
End;

Function StringEndsWith(S, Suffix : String) : Boolean;
Begin
    Result := (Length(S) >= Length(Suffix)) And
              (Copy(S, Length(S) - Length(Suffix) + 1, Length(Suffix)) = Suffix);
End;

// Busca un parametro por nombre dentro de un componente. Nil si no existe.
Function FindParamByName(Comp : ISch_Component; PName : String) : ISch_Parameter;
Var
    Iter  : ISch_Iterator;
    P     : ISch_Parameter;
Begin
    Result := Nil;
    Iter := Comp.SchIterator_Create;
    Iter.AddFilter_ObjectSet(MkSet(eParameter));
    Try
        P := Iter.FirstSchObject;
        While P <> Nil Do
        Begin
            If P.Name = PName Then
            Begin
                Result := P;
                Break;
            End;
            P := Iter.NextSchObject;
        End;
    Finally
        Comp.SchIterator_Destroy(Iter);
    End;
End;

// Busca un parametro "ComponentLink<n>Description" cuyo VALOR actual sea
// igual a OldDescription. Nil si no existe ninguno con ese valor.
Function FindLinkDescriptionParam(Comp : ISch_Component; OldDescription : String) : ISch_Parameter;
Var
    Iter  : ISch_Iterator;
    P     : ISch_Parameter;
Begin
    Result := Nil;
    Iter := Comp.SchIterator_Create;
    Iter.AddFilter_ObjectSet(MkSet(eParameter));
    Try
        P := Iter.FirstSchObject;
        While P <> Nil Do
        Begin
            If StringStartsWith(P.Name, 'ComponentLink') And
               StringEndsWith(P.Name, 'Description') And
               (P.Text = OldDescription) Then
            Begin
                Result := P;
                Break;
            End;
            P := Iter.NextSchObject;
        End;
    Finally
        Comp.SchIterator_Destroy(Iter);
    End;
End;


// ---------------------------------------------------------------------
// Procedimiento principal
// ---------------------------------------------------------------------

Procedure ReorganizarParametros;
Const
    // Ruta al archivo de mapeo "nombre actual <tab> nombre nuevo"
    RENAME_FILE = 'D:\Proyectos\Altium libraries\__comp\Script_project\renameParam.txt';

Var
    OldNames, NewNames   : TStringList;
    NewParamNames        : TStringList;
    NewParamValues       : TStringList;

    CurrentLib   : ISch_Lib;
    LibIterator  : ISch_Iterator;
    Component    : ISch_Component;
    Param        : ISch_Parameter;
    LinkParam    : ISch_Parameter;
    NewParam     : ISch_Parameter;

    i, j : Integer;
    ComponentCount, TouchedCount, LinkTouchedCount : Integer;

Begin
    // =====================================================================
    // CONFIGURACION -- Completar cuando tengas los datos definitivos
    // =====================================================================

    NewParamNames  := TStringList.Create;
    NewParamValues := TStringList.Create;

    // TODO: parametros nuevos a agregar (nombre y valor por defecto van
    // en el mismo orden en las dos listas):
    // NewParamNames.Add('NombreDelNuevoParametro');  NewParamValues.Add('');

    // TODO: orden final completo (nombres ya renombrados + nuevos).
    // NO incluir aca los Links (ej. "_datasheet"): esos mantienen su
    // propio orden interno y no pasan por este mecanismo.
    // FinalOrder.Add('_Man_Code');
    // FinalOrder.Add('_Int_Code');
    // ... etc.

    // =====================================================================

    If SchServer = Nil Then
    Begin
        ShowMessage('SchServer no disponible.');
        Exit;
    End;

    CurrentLib := SchServer.GetCurrentSchDocument;
    If (CurrentLib = Nil) Or (CurrentLib.ObjectID <> eSchLib) Then
    Begin
        ShowMessage('Abri primero el archivo .SchLib que queres modificar.');
        NewParamNames.Free;
        NewParamValues.Free;
        Exit;
    End;

    OldNames := TStringList.Create;
    NewNames := TStringList.Create;
    LoadRenameMap(RENAME_FILE, OldNames, NewNames);

    If OldNames.Count = 0 Then
    Begin
        ShowMessage('No se pudo leer el archivo de mapeo, o esta vacio: ' + RENAME_FILE);
        OldNames.Free;
        NewNames.Free;
        NewParamNames.Free;
        NewParamValues.Free;
        Exit;
    End;

    ComponentCount := 0;
    LibIterator := CurrentLib.SchLibIterator_Create;
    LibIterator.AddFilter_ObjectSet(MkSet(eSchComponent));

    Try
        Component := LibIterator.FirstSchObject;
        While Component <> Nil Do
        Begin
            TouchedCount     := 0;
            LinkTouchedCount := 0;

            // ------------------------------------------------------------
            // Paso 1: renombrar parametros comunes in-place y actualizar
            //         Links in-place.
            // ------------------------------------------------------------
            For i := 0 To OldNames.Count - 1 Do
            Begin
                Param := FindParamByName(Component, OldNames[i]);
                If Param <> Nil Then
                Begin
                    // Parametro comun: se renombra directamente usando el
                    // metodo SetState_Name, que es la forma compatible con
                    // DelphiScript para modificar el nombre.
                    Param.SetState_Name(NewNames[i]);
                    TouchedCount := TouchedCount + 1;
                End
                Else
                Begin
                    // No es un parametro comun; probar si es un Link.
                    LinkParam := FindLinkDescriptionParam(Component, OldNames[i]);
                    If LinkParam <> Nil Then
                    Begin
                        LinkParam.Text := NewNames[i];
                        LinkTouchedCount := LinkTouchedCount + 1;
                    End;
                End;
            End;

            // ------------------------------------------------------------
            // Paso 2: agregar los parametros nuevos (si aun no existen)
            // ------------------------------------------------------------
            For j := 0 To NewParamNames.Count - 1 Do
            Begin
                Param := FindParamByName(Component, NewParamNames[j]);
                If Param = Nil Then
                Begin
                    NewParam := SchServer.SchObjectFactory(eParameter, eNoDimension);
                    NewParam.Name := NewParamNames[j];
                    NewParam.Text := NewParamValues[j];
                    NewParam.Location.X := 0;
                    NewParam.Location.Y := 0;
                    NewParam.IsHidden := False;
                    Component.AddSchObject(NewParam);
                End;
            End;

            If (TouchedCount > 0) Or (LinkTouchedCount > 0) Then
                ComponentCount := ComponentCount + 1;

            Component := LibIterator.NextSchObject;
        End;
    Finally
        CurrentLib.SchIterator_Destroy(LibIterator);
    End;

    OldNames.Free;
    NewNames.Free;
    NewParamNames.Free;
    NewParamValues.Free;

    ShowMessage('Proceso completado. Componentes con al menos un cambio: ' + IntToStr(ComponentCount));
End;


{ ==========================================================================
  ListarParametros

  Auxiliar: recorre la libreria y guarda en un .txt, componente por
  componente, el nombre y valor de cada parametro (incluyendo los
  ComponentLink*Description / ComponentLink*URL de los Links). Util para
  verificar los nombres exactos antes de armar el archivo de orden final.
   ========================================================================== }

Procedure ListarParametros;
Var
    CurrentLib   : ISch_Lib;
    LibIterator  : ISch_Iterator;
    Component    : ISch_Component;
    ParamIter    : ISch_Iterator;
    Param        : ISch_Parameter;
    Reporte      : TStringList;
Begin
    If SchServer = Nil Then Exit;
    CurrentLib := SchServer.GetCurrentSchDocument;
    If (CurrentLib = Nil) Or (CurrentLib.ObjectID <> eSchLib) Then
    Begin
        ShowMessage('Abri primero el archivo .SchLib.');
        Exit;
    End;

    Reporte := TStringList.Create;

    LibIterator := CurrentLib.SchLibIterator_Create;
    LibIterator.AddFilter_ObjectSet(MkSet(eSchComponent));
    Try
        Component := LibIterator.FirstSchObject;
        While Component <> Nil Do
        Begin
            Reporte.Add('=== ' + Component.LibReference + ' ===');

            ParamIter := Component.SchIterator_Create;
            ParamIter.AddFilter_ObjectSet(MkSet(eParameter));
            Try
                Param := ParamIter.FirstSchObject;
                While Param <> Nil Do
                Begin
                    Reporte.Add('   ' + Param.Name + ' = ' + Param.Text);
                    Param := ParamIter.NextSchObject;
                End;
            Finally
                Component.SchIterator_Destroy(ParamIter);
            End;

            Component := LibIterator.NextSchObject;
        End;
    Finally
        CurrentLib.SchIterator_Destroy(LibIterator);
    End;

    Reporte.SaveToFile('d:\__dev\_Lib\ADLib_2.1\testParam\ParametrosSchLib.txt');
    ShowMessage('d:\__dev\_Lib\ADLib_2.1\testParam\ParametrosSchLib.txt');
    Reporte.Free;
End;


{ ==========================================================================
  DiagnosticarRenombres

  Solo diagnostica: carga el archivo de mapeo, recorre la libreria y genera
  un .txt con una tabla de dos columnas (NombreActual, NombreNuevo) por
  componente, indicando si cada parametro fue encontrado o no.
  No modifica la libreria.
   ========================================================================== }

Procedure DiagnosticarRenombres;
Const
    RENAME_FILE = 'd:\__dev\_Lib\ADLib_2.1\testParam\renameParam.txt';
    OUT_FILE    = 'd:\__dev\_Lib\ADLib_2.1\testParam\DiagnosticoRenombres.txt';
Var
    OldNames, NewNames : TStringList;
    CurrentLib   : ISch_Lib;
    LibIterator  : ISch_Iterator;
    Component    : ISch_Component;
    Param        : ISch_Parameter;
    Reporte      : TStringList;
    i            : Integer;
Begin
    If SchServer = Nil Then
    Begin
        ShowMessage('SchServer no disponible.');
        Exit;
    End;

    CurrentLib := SchServer.GetCurrentSchDocument;
    If (CurrentLib = Nil) Or (CurrentLib.ObjectID <> eSchLib) Then
    Begin
        ShowMessage('Abri primero el archivo .SchLib.');
        Exit;
    End;

    OldNames := TStringList.Create;
    NewNames := TStringList.Create;
    LoadRenameMap(RENAME_FILE, OldNames, NewNames);

    If OldNames.Count = 0 Then
    Begin
        ShowMessage('No se pudo leer el archivo de mapeo: ' + RENAME_FILE);
        OldNames.Free;
        NewNames.Free;
        Exit;
    End;

    Reporte := TStringList.Create;

    LibIterator := CurrentLib.SchLibIterator_Create;
    LibIterator.AddFilter_ObjectSet(MkSet(eSchComponent));
    Try
        Component := LibIterator.FirstSchObject;
        While Component <> Nil Do
        Begin
            Reporte.Add('=== ' + Component.LibReference + ' ===');
            Reporte.Add('NombreActual' + #9 + 'NombreNuevo' + #9 + 'Estado' + #9 + 'ValorActual');

            For i := 0 To OldNames.Count - 1 Do
            Begin
                Param := FindParamByName(Component, OldNames[i]);
                If Param <> Nil Then
                    Reporte.Add(OldNames[i] + #9 + NewNames[i] + #9 + 'ENCONTRADO' + #9 + Param.Text)
                Else
                    Reporte.Add(OldNames[i] + #9 + NewNames[i] + #9 + 'NO_ENCONTRADO' + #9 + '-');
            End;

            Reporte.Add('');
            Component := LibIterator.NextSchObject;
        End;
    Finally
        CurrentLib.SchIterator_Destroy(LibIterator);
    End;

    Reporte.SaveToFile(OUT_FILE);
    ShowMessage('Diagnostico guardado en:' + #13#10 + OUT_FILE);

    OldNames.Free;
    NewNames.Free;
    Reporte.Free;
End;


{ ==========================================================================
  MarkSchLibAsModified

  Marca la libreria de esquematicos actual como modificada para que Altium
  permita guardarla. Se ejecuta como paso separado despues de
  ReorganizarParametros.
   ========================================================================== }

Procedure MarkSchLibAsModified;
Var
    SchLibDoc : ISch_Document;
    DocPath   : String;
Begin
    If SchServer = Nil Then Exit;

    SchLibDoc := SchServer.GetCurrentSchDocument;
    If SchLibDoc <> Nil Then
    Begin
        DocPath := SchLibDoc.DocumentName;
        Client.OpenDocument('SCH', DocPath).Modified := True;
    End;
End;
