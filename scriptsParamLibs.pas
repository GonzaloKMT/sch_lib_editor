Procedure ReorderLibraryParameters;
Var
    CurrentLib      : ISch_Lib;
    CompIterator    : ISch_Iterator;
    ParamIterator   : ISch_Iterator;
    SchComponent    : ISch_Component;
    Param           : ISch_Parameter;
    OldParam        : ISch_Parameter;
    NewParam        : ISch_Parameter;
    ParamNames      : TStringList;
    ParamValues     : TStringList;
    MasterOrder     : TStringList;
    LinkSourceNames : TStringList;
    LinkLabels      : TStringList;
    i               : Integer;
    NameKey         : String;
    Idx             : Integer;
    LinkIndex       : Integer;
Begin
    CurrentLib := SchServer.GetCurrentSchDocument;
    If CurrentLib = Nil Then Exit;

    MasterOrder := TStringList.Create;
    MasterOrder.Add('_Man_Code');
    MasterOrder.Add('_Man_Name');
    MasterOrder.Add('_Ref_Price');
    MasterOrder.Add('_Ad_Esp1');
    MasterOrder.Add('_Ad_Esp2');
    MasterOrder.Add('_Ad_Esp3');
    MasterOrder.Add('_Ad_Esp4');
    MasterOrder.Add('_Ad_Esp5');
    MasterOrder.Add('_Package');
    MasterOrder.Add('_SMD');
    MasterOrder.Add('_Date');
    MasterOrder.Add('_Active');
    MasterOrder.Add('_Int_PartNum');
    MasterOrder.Add('_Int_Desc');
    MasterOrder.Add('_Man1_Code');
    MasterOrder.Add('_Man1_Name');
    MasterOrder.Add('_Man2_Code');
    MasterOrder.Add('_Man2_Name');
    MasterOrder.Add('_Man3_Code');
    MasterOrder.Add('_Man3_Name');
    MasterOrder.Add('_Prov1_Name');
    MasterOrder.Add('_Prov1_Code');
    MasterOrder.Add('_Prov1_Price');
    MasterOrder.Add('_Prov2_Name');
    MasterOrder.Add('_Prov2_Code');
    MasterOrder.Add('_Prov2_Price');
    MasterOrder.Add('_Prov3_Name');
    MasterOrder.Add('_Prov3_Code');
    MasterOrder.Add('_Prov3_Price');
    MasterOrder.Add('_Prov4_Name');
    MasterOrder.Add('_Prov4_Code');
    MasterOrder.Add('_Prov4_Price');
    MasterOrder.Add('_FoSupply');

    LinkSourceNames := TStringList.Create;
    LinkLabels       := TStringList.Create;
    LinkSourceNames.Add('_Datasheet');   LinkLabels.Add('Datasheet');
    LinkSourceNames.Add('_Prov1_Lnk');   LinkLabels.Add('Proveedor 1');
    LinkSourceNames.Add('_Prov2_Lnk');   LinkLabels.Add('Proveedor 2');
    LinkSourceNames.Add('_Prov3_Lnk');   LinkLabels.Add('Proveedor 3');
    LinkSourceNames.Add('_Prov4_Lnk');   LinkLabels.Add('Proveedor 4');

    SchServer.ProcessControl.PreProcess(CurrentLib, '');
    Try
        CompIterator := CurrentLib.SchLibIterator_Create;
        SchComponent := CompIterator.FirstSchObject;

        While SchComponent <> Nil Do
        Begin
            ParamNames  := TStringList.Create;
            ParamValues := TStringList.Create;

            // --- Leer y guardar los parámetros actuales ---
            ParamIterator := SchComponent.SchIterator_Create;
            ParamIterator.AddFilter_ObjectSet(MkSet(eParameter));
            Param := ParamIterator.FirstSchObject;
            While Param <> Nil Do
            Begin
                ParamNames.Add(Param.Name);
                ParamValues.Add(Param.Text);
                Param := ParamIterator.NextSchObject;
            End;
            SchComponent.SchIterator_Destroy(ParamIterator);

            // --- Borrar los parámetros actuales (patrón seguro + registro) ---
            ParamIterator := SchComponent.SchIterator_Create;
            ParamIterator.AddFilter_ObjectSet(MkSet(eParameter));
            Param := ParamIterator.FirstSchObject;
            While Param <> Nil Do
            Begin
                OldParam := Param;
                Param := ParamIterator.NextSchObject;
                SchComponent.RemoveSchObject(OldParam);
                SchServer.RobotManager.SendMessage(SchComponent.I_ObjectAddress, c_BroadCast, SCHM_PrimitiveRegistration, OldParam.I_ObjectAddress);
            End;
            SchComponent.SchIterator_Destroy(ParamIterator);

            // --- Recrear parámetros normales, en el orden maestro ---
            For i := 0 To MasterOrder.Count - 1 Do
            Begin
                NameKey := MasterOrder[i];
                Idx := ParamNames.IndexOf(NameKey);
                If Idx >= 0 Then
                Begin
                    NewParam := SchServer.SchObjectFactory(eParameter, eCreate_Default);
                    NewParam.Name     := NameKey;
                    NewParam.Text     := ParamValues[Idx];
                    NewParam.IsHidden := True;
                    SchComponent.AddSchObject(NewParam);
                    SchServer.RobotManager.SendMessage(SchComponent.I_ObjectAddress, c_BroadCast, SCHM_PrimitiveRegistration, NewParam.I_ObjectAddress);
                End;
            End;

            // --- Recrear los Links, en el orden deseado (incluso si están vacíos) ---
            LinkIndex := 1;
            For i := 0 To LinkSourceNames.Count - 1 Do
            Begin
                NameKey := LinkSourceNames[i];
                Idx := ParamNames.IndexOf(NameKey);
                If Idx >= 0 Then
                Begin
                    NewParam := SchServer.SchObjectFactory(eParameter, eCreate_Default);
                    NewParam.Name     := 'ComponentLink' + IntToStr(LinkIndex) + 'URL';
                    NewParam.Text     := ParamValues[Idx];
                    NewParam.IsHidden := True;
                    SchComponent.AddSchObject(NewParam);
                    SchServer.RobotManager.SendMessage(SchComponent.I_ObjectAddress, c_BroadCast, SCHM_PrimitiveRegistration, NewParam.I_ObjectAddress);

                    NewParam := SchServer.SchObjectFactory(eParameter, eCreate_Default);
                    NewParam.Name     := 'ComponentLink' + IntToStr(LinkIndex) + 'Description';
                    NewParam.Text     := LinkLabels[i];
                    NewParam.IsHidden := True;
                    SchComponent.AddSchObject(NewParam);
                    SchServer.RobotManager.SendMessage(SchComponent.I_ObjectAddress, c_BroadCast, SCHM_PrimitiveRegistration, NewParam.I_ObjectAddress);

                    LinkIndex := LinkIndex + 1;
                End;
            End;

            ParamNames.Free;
            ParamValues.Free;

            SchComponent := CompIterator.NextSchObject;
        End;

        CurrentLib.SchIterator_Destroy(CompIterator);
    Finally
        SchServer.ProcessControl.PostProcess(CurrentLib, '');
    End;

    MasterOrder.Free;
    LinkSourceNames.Free;
    LinkLabels.Free;
    ShowMessage('Reordenamiento y conversión de Links completados.');
End;

