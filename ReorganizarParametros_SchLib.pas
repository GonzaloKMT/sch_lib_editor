{ ==========================================================================
  ReorganizarParametros_SchLib.pas

  El codigo de este archivo se movio a EditLib.pas: DelphiScript no permite
  acceder de forma confiable a variables/procedimientos "top level" de un
  archivo desde otro archivo del mismo proyecto (aparecian los errores
  "Can't access top level variable" / "Invalid procedure usage"). Al
  unificar formulario y logica en un solo archivo, ese problema desaparece.

  Ver EditLib.pas para ReorganizarParametros, ListarParametros,
  DiagnosticarRenombres, MarkSchLibAsModified y el formulario (ShowEditLibForm).
   ========================================================================== }
