{ ==========================================================================
  EditLib.pas

  Formulario + logica de reorganizacion de parametros.

  ESTRUCTURA (importante):
    Este archivo sigue el patron real de los scripts de formulario de
    Altium (ver ejemplo oficial "PCB Logo Creator" > Converter.PAS): SIN
  unit ... interface ... implementation", SIN declarar manualmente
    type TForm1 = class(TForm) ... end" y SIN " Altium arma
    la clase TForm1 y la instancia global Form1 el solo a partir del
    EditLib.dfm (mismo nombre base que este archivo); aca solo hace falta
    implementar los metodos de evento (Procedure TForm1.Metodo(...)) y
    referenciar Form1 directamente.

    Las variables declaradas "sueltas" (Var ... antes de cualquier
    Procedure/Function) son globales del script y se pueden leer/escribir
    tanto desde procedimientos comunes como desde los manejadores de
    eventos del formulario sin restriccion.

  LOGICA CONSERVADORA:
    ReorganizarParametros SOLO toca los parametros que vos declaraste
    explicitamente (en el archivo de renombres y en NEW_PARAMS mas abajo).
    Cualquier otro parametro del componente -sea del sistema (Comment,
    Designator, Value, Footprint, etc.) o cualquier parametro propio que
    no hayas listado- NO se lee, NO se borra, NO se mueve y NO se modifica
    de ninguna forma.

  CASO ESPECIAL: PARAMETROS TIPO "LINK"
    Cuando en Altium se agrega un campo usando Add > Link (en vez de
    Add > Parameter), NO se crea un parametro comun. Internamente se crean
    DOS parametros con nombres tipo:
        ComponentLink<n>Description   -> guarda el "nombre" que se ve
        ComponentLink<n>URL           -> guarda la URL / ruta de destino
    (<n> es el numero de indice del link: 1, 2, 3, etc.)

    Por eso, para renombrar algo como "_Man_Lnk" (que en realidad es el
    VALOR del parametro ComponentLinkNDescription, no un nombre de
    parametro real), ReorganizarParametros:
      1) Primero intenta encontrarlo como parametro normal (por Name).
      2) Si no lo encuentra, revisa si es un Link: busca un parametro
         "ComponentLink*Description" cuyo VALOR actual coincida con el
         nombre viejo, y en ese caso solo le cambia el valor (la
         "descripcion") al nombre nuevo. El "ComponentLink*URL" asociado
         NO se toca en ningun momento, para no perder la URL real.
      3) Este tipo de entrada NO participa del reordenamiento general:
         Altium maneja el orden de los Links con su propio indice interno
         <n>, que se usa para el submenu References, y no es parte de la
         grilla general de parametros.

  ANTES DE CORRERLO:
    - Backup del .SchLib. El script modifica todos los componentes de la
      libreria abierta.
    - El archivo de mapeo se elige corriendo ShowEditLibForm y usando el
      boton "Examinar...". Si no se abre el formulario o no se elige
      ningun archivo, se usa DEFAULT_RENAME_FILE (mas abajo).
    - Completa la seccion NEW_PARAMS con los parametros nuevos (cuando
      los tengas).
    - Completa la seccion FINAL_ORDER con el orden definitivo (cuando lo
      tengas).

  IMPORTANTE (limitacion tecnica de DelphiScript):
    DelphiScript NO soporta arrays dinamicos ("Array Of Tipo" + SetLength).
    Por eso NEW_PARAMS y FINAL_ORDER se cargan usando TStringList.Add(),
    en vez de asignar por indice como en Delphi normal.
   ========================================================================== }

uses
    AltiumScripting,
    SchLib,
    SchDoc;

Var
    // Ruta de archivo elegida en el formulario (Edit1.Text). Vacia hasta
    // que el usuario elija un archivo con "Examinar..." -- no hay ruta
    // por defecto.
    SelectedRenameFile : String;

    // Ruta del archivo con la lista de parametros a agregar
    // (EditParamListFile.Text). Vacia hasta que se elija uno.
    ParamListFile : String;


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

// Carga una lista simple de nombres de parametros (un nombre por renglon)
// en Names (debe venir creada). Ignora renglones vacios y comentarios
// "// ...".
Procedure LoadParamNameList(FilePath : String; Names : TStringList);
Var
    RawLines : TStringList;
    i        : Integer;
    Line     : String;
    p        : Integer;
Begin
    Names.Clear;

    RawLines := TStringList.Create;
    Try
        RawLines.LoadFromFile(FilePath);
        For i := 0 To RawLines.Count - 1 Do
        Begin
            Line := RawLines[i];

            p := Pos('//', Line);
            If p > 0 Then Line := Copy(Line, 1, p - 1);

            Line := Trim(Line);
            If Line <> '' Then Names.Add(Line);
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

// Dummy: sin uso, solo evita que este procedimiento aparezca en la lista
// de "Run Script" de Altium (que solo ofrece procedimientos sin
// parametros) -- se debe correr desde el boton del formulario.
Procedure ReorganizarParametros(Dummy : Integer);
Var
    RenameFile           : String;
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

    // Ruta del archivo de mapeo: la elegida en el formulario (Edit1). No
    // hay valor por defecto -- hay que elegir un archivo con "Examinar...".
    RenameFile := SelectedRenameFile;
    If Trim(RenameFile) = '' Then
    Begin
        ShowMessage('Elegi primero el archivo de mapeo con el boton "Examinar...".');
        NewParamNames.Free;
        NewParamValues.Free;
        Exit;
    End;

    OldNames := TStringList.Create;
    NewNames := TStringList.Create;
    LoadRenameMap(RenameFile, OldNames, NewNames);

    If OldNames.Count = 0 Then
    Begin
        ShowMessage('No se pudo leer el archivo de mapeo, o esta vacio: ' + RenameFile);
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

// Dummy: ver comentario en ReorganizarParametros.
Procedure ListarParametros(Dummy : Integer);
Var
    CurrentLib   : ISch_Lib;
    LibIterator  : ISch_Iterator;
    Component    : ISch_Component;
    ParamIter    : ISch_Iterator;
    Param        : ISch_Parameter;
    Reporte      : TStringList;
    OutFile      : String;
    LibName      : String;
Begin
    If SchServer = Nil Then Exit;
    CurrentLib := SchServer.GetCurrentSchDocument;
    If (CurrentLib = Nil) Or (CurrentLib.ObjectID <> eSchLib) Then
    Begin
        ShowMessage('Abri primero el archivo .SchLib.');
        Exit;
    End;

    LibName := ChangeFileExt(ExtractFileName(CurrentLib.DocumentName), '');

    SaveDialog1.Filter   := 'Archivos de texto (*.txt)|*.txt|Todos los archivos (*.*)|*.*';
    SaveDialog1.FileName := 'parametros_' + LibName + '.txt';
    If Not SaveDialog1.Execute Then Exit;

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

    OutFile := SaveDialog1.FileName;
    Reporte.SaveToFile(OutFile);
    ShowMessage(OutFile);
    Reporte.Free;
End;


{ ==========================================================================
  DiagnosticarRenombres

  Solo diagnostica: carga el archivo de mapeo, recorre la libreria y genera
  un .txt con una tabla de dos columnas (NombreActual, NombreNuevo) por
  componente, indicando si cada parametro fue encontrado o no.
  No modifica la libreria.
   ========================================================================== }

// Dummy: ver comentario en ReorganizarParametros.
Procedure DiagnosticarRenombres(Dummy : Integer);
Var
    OldNames, NewNames : TStringList;
    CurrentLib   : ISch_Lib;
    LibIterator  : ISch_Iterator;
    Component    : ISch_Component;
    Param        : ISch_Parameter;
    Reporte      : TStringList;
    i            : Integer;
    OutFile      : String;
    LibName      : String;
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

    If Trim(SelectedRenameFile) = '' Then
    Begin
        ShowMessage('Elegi primero el archivo de mapeo con el boton "Examinar...".');
        Exit;
    End;

    OldNames := TStringList.Create;
    NewNames := TStringList.Create;
    LoadRenameMap(SelectedRenameFile, OldNames, NewNames);

    If OldNames.Count = 0 Then
    Begin
        ShowMessage('No se pudo leer el archivo de mapeo: ' + SelectedRenameFile);
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

    // Se guarda en el mismo directorio que el archivo de mapeo elegido
    // con "Examinar...".
    LibName := ChangeFileExt(ExtractFileName(CurrentLib.DocumentName), '');
    OutFile := ExtractFilePath(SelectedRenameFile) + 'DiagnosticoRenombres_' + LibName + '.txt';
    Reporte.SaveToFile(OutFile);
    ShowMessage('Diagnostico guardado en:' + #13#10 + OutFile);

    OldNames.Free;
    NewNames.Free;
    Reporte.Free;
End;


{ ==========================================================================
  MarkSchLibAsModified

  Marca la libreria de esquematicos actual como modificada para que Altium
  permita guardarla. Se corre automaticamente despues de
  ReorganizarParametros (boton "Ejecutar reorganizacion").
   ========================================================================== }

// Dummy: ver comentario en ReorganizarParametros.
Procedure MarkSchLibAsModified(Dummy : Integer);
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


{ ==========================================================================
  AgregarParametrosATodos

  Lee una lista de nombres de parametros desde ParamListFile (un nombre
  por renglon). Para cada componente de la libreria abierta:
    1) Agrega, con valor vacio, los parametros de la lista que todavia
       no tenga. Los que ya tiene NO se tocan (conserva su valor).
    2) Reordena TODOS sus parametros comunes para que queden en el mismo
       orden que la lista del archivo; los parametros existentes que no
       aparecen en la lista se agrupan al final, conservando el orden
       relativo que ya tenian entre si.

  Los parametros tipo Link (ComponentLink<n>Description / ...URL, ver
  encabezado de este archivo) NO participan de este reordenamiento:
  Altium los ordena con su propio indice interno <n>, no con la posicion
  en la grilla general de parametros.
   ========================================================================== }

// Dummy: ver comentario en ReorganizarParametros.
Procedure AgregarParametrosATodos(Dummy : Integer);
Var
    CurrentLib      : ISch_Lib;
    LibIterator     : ISch_Iterator;
    Component       : ISch_Component;
    ParamIterator   : ISch_Iterator;
    Param           : ISch_Parameter;
    OldParam        : ISch_Parameter;
    NewParam        : ISch_Parameter;
    ParamListNames  : TStringList;
    ExistingNames   : TStringList;
    ExistingValues  : TStringList;
    ExistingHidden  : TStringList;
    ExistingLocX    : TStringList;
    ExistingLocY    : TStringList;
    FinalOrder      : TStringList;
    i, Idx          : Integer;
    NameKey         : String;
    Changed         : Boolean;
    ComponentCount  : Integer;
    AddedCount      : Integer;
Begin
    If SchServer = Nil Then
    Begin
        ShowMessage('SchServer no disponible.');
        Exit;
    End;

    CurrentLib := SchServer.GetCurrentSchDocument;
    If (CurrentLib = Nil) Or (CurrentLib.ObjectID <> eSchLib) Then
    Begin
        ShowMessage('Abri primero el archivo .SchLib que queres modificar.');
        Exit;
    End;

    If Trim(ParamListFile) = '' Then
    Begin
        ShowMessage('Elegi primero el archivo con la lista de parametros con el boton "Examinar...".');
        Exit;
    End;

    ParamListNames := TStringList.Create;
    LoadParamNameList(ParamListFile, ParamListNames);

    If ParamListNames.Count = 0 Then
    Begin
        ShowMessage('No se pudo leer la lista de parametros, o esta vacia: ' + ParamListFile);
        ParamListNames.Free;
        Exit;
    End;

    ComponentCount := 0;
    AddedCount     := 0;

    SchServer.ProcessControl.PreProcess(CurrentLib, '');
    Try
        LibIterator := CurrentLib.SchLibIterator_Create;
        LibIterator.AddFilter_ObjectSet(MkSet(eSchComponent));
        Try
            Component := LibIterator.FirstSchObject;
            While Component <> Nil Do
            Begin
                ExistingNames  := TStringList.Create;
                ExistingValues := TStringList.Create;
                ExistingHidden := TStringList.Create;
                ExistingLocX   := TStringList.Create;
                ExistingLocY   := TStringList.Create;

                // Leer los parametros comunes actuales (los Links no
                // entran en este reordenamiento).
                ParamIterator := Component.SchIterator_Create;
                ParamIterator.AddFilter_ObjectSet(MkSet(eParameter));
                Param := ParamIterator.FirstSchObject;
                While Param <> Nil Do
                Begin
                    If Not StringStartsWith(Param.Name, 'ComponentLink') Then
                    Begin
                        ExistingNames.Add(Param.Name);
                        ExistingValues.Add(Param.Text);
                        If Param.IsHidden Then
                            ExistingHidden.Add('H')
                        Else
                            ExistingHidden.Add('V');
                        ExistingLocX.Add(IntToStr(Param.Location.X));
                        ExistingLocY.Add(IntToStr(Param.Location.Y));
                    End;
                    Param := ParamIterator.NextSchObject;
                End;
                Component.SchIterator_Destroy(ParamIterator);

                // Orden final: primero los de la lista (en ese orden),
                // despues los existentes que no estan en la lista, en el
                // orden relativo en que ya estaban.
                FinalOrder := TStringList.Create;
                For i := 0 To ParamListNames.Count - 1 Do
                    FinalOrder.Add(ParamListNames[i]);
                For i := 0 To ExistingNames.Count - 1 Do
                Begin
                    If FinalOrder.IndexOf(ExistingNames[i]) < 0 Then
                        FinalOrder.Add(ExistingNames[i]);
                End;

                // Si el orden actual ya coincide con el final, no tocar
                // el componente.
                Changed := (ExistingNames.Count <> FinalOrder.Count);
                If Not Changed Then
                Begin
                    For i := 0 To FinalOrder.Count - 1 Do
                    Begin
                        If ExistingNames[i] <> FinalOrder[i] Then
                        Begin
                            Changed := True;
                            Break;
                        End;
                    End;
                End;

                If Changed Then
                Begin
                    For i := 0 To ParamListNames.Count - 1 Do
                    Begin
                        If ExistingNames.IndexOf(ParamListNames[i]) < 0 Then
                            AddedCount := AddedCount + 1;
                    End;

                    // Borrar los parametros comunes actuales (patron
                    // seguro: guardar el siguiente antes de borrar).
                    ParamIterator := Component.SchIterator_Create;
                    ParamIterator.AddFilter_ObjectSet(MkSet(eParameter));
                    Param := ParamIterator.FirstSchObject;
                    While Param <> Nil Do
                    Begin
                        OldParam := Param;
                        Param := ParamIterator.NextSchObject;
                        If Not StringStartsWith(OldParam.Name, 'ComponentLink') Then
                        Begin
                            Component.RemoveSchObject(OldParam);
                            SchServer.RobotManager.SendMessage(Component.I_ObjectAddress, c_BroadCast, SCHM_PrimitiveRegistration, OldParam.I_ObjectAddress);
                        End;
                    End;
                    Component.SchIterator_Destroy(ParamIterator);

                    // Recrearlos en el orden final, conservando valor y
                    // visibilidad de los que ya existian.
                    For i := 0 To FinalOrder.Count - 1 Do
                    Begin
                        NameKey := FinalOrder[i];
                        Idx     := ExistingNames.IndexOf(NameKey);

                        NewParam := SchServer.SchObjectFactory(eParameter, eCreate_Default);
                        NewParam.Name := NameKey;
                        If Idx >= 0 Then
                        Begin
                            NewParam.Text        := ExistingValues[Idx];
                            NewParam.IsHidden    := True;//(ExistingHidden[Idx] = 'H');
                            NewParam.Location.X  := StrToInt(ExistingLocX[Idx]);
                            NewParam.Location.Y  := StrToInt(ExistingLocY[Idx]);
                        End
                        Else
                        Begin
                            NewParam.Text        := '';
                            NewParam.IsHidden    := True;
                            NewParam.Location.X  := 0;
                            NewParam.Location.Y  := 0;
                        End;
                        Component.AddSchObject(NewParam);
                        SchServer.RobotManager.SendMessage(Component.I_ObjectAddress, c_BroadCast, SCHM_PrimitiveRegistration, NewParam.I_ObjectAddress);
                    End;

                    ComponentCount := ComponentCount + 1;
                End;

                ExistingNames.Free;
                ExistingValues.Free;
                ExistingHidden.Free;
                ExistingLocX.Free;
                ExistingLocY.Free;
                FinalOrder.Free;

                Component := LibIterator.NextSchObject;
            End;
        Finally
            CurrentLib.SchIterator_Destroy(LibIterator);
        End;
    Finally
        SchServer.ProcessControl.PostProcess(CurrentLib, '');
    End;

    ParamListNames.Free;

    ShowMessage('Componentes actualizados: ' + IntToStr(ComponentCount) +
                '. Parametros nuevos agregados en total: ' + IntToStr(AddedCount) + '.');
End;


// ---------------------------------------------------------------------
// Formulario
// ---------------------------------------------------------------------

// Muestra el formulario de configuracion. Form1 (la instancia de
// TForm1) la crea Altium automaticamente a partir de EditLib.dfm; no
// hace falta (ni se debe) declararla o crearla a mano.
Procedure ShowEditLibForm;
Begin
    Form1.ShowModal;
End;

Procedure TForm1.FormCreate(Sender: TObject);
Begin
    Edit1.Text := '';
    SelectedRenameFile := '';

    EditParamListFile.Text := '';
    ParamListFile := '';
End;

Procedure TForm1.BtnSeleccionarArchivoClick(Sender: TObject);
Begin
    OpenDialog1.Filter := 'Archivos de texto (*.txt)|*.txt|Todos los archivos (*.*)|*.*';
    If Trim(Edit1.Text) <> '' Then
        OpenDialog1.FileName := Edit1.Text;
    If OpenDialog1.Execute Then
    Begin
        Edit1.Text := OpenDialog1.FileName;
        SelectedRenameFile := Edit1.Text;
    End;
End;

Procedure TForm1.BtnSeleccionarParamListClick(Sender: TObject);
Begin
    OpenDialog1.Filter := 'Archivos de texto (*.txt)|*.txt|Todos los archivos (*.*)|*.*';
    If Trim(EditParamListFile.Text) <> '' Then
        OpenDialog1.FileName := EditParamListFile.Text;
    If OpenDialog1.Execute Then
    Begin
        EditParamListFile.Text := OpenDialog1.FileName;
        ParamListFile := EditParamListFile.Text;
    End;
End;

Procedure TForm1.BtnEjecutarClick(Sender: TObject);
Begin
    ReorganizarParametros(0);
    MarkSchLibAsModified(0);
End;

Procedure TForm1.BtnDiagnosticarClick(Sender: TObject);
Begin
    DiagnosticarRenombres(0);
End;

Procedure TForm1.BtnListarParametrosClick(Sender: TObject);
Begin
    ListarParametros(0);
End;

Procedure TForm1.BtnAgregarParametroClick(Sender: TObject);
Begin
    AgregarParametrosATodos(0);
    MarkSchLibAsModified(0);
End;
