/* Sincronización de Nuestra Casa. Solo usa la clave publishable de Supabase; nunca debe incluirse una service_role key. */
(function(){
  const SUPABASE_URL = "https://hfvithoioqugzgiuiihi.supabase.co";
  const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_RP7lITb4YL9ey_bi1tVvwA_RECSYHa1";
  let client = null, householdId = null, user = null, ready = false, timer = null, busy = false, queued = false;

  const $ = (s) => document.querySelector(s);
  function status(msg, good=false){
    const el = $("#syncStatus");
    if(el){ el.textContent = msg; el.style.color = good ? "#23834a" : "var(--muted)"; }
  }
  function showConnected(ok){
    const f=$("#syncLoginForm"), b=$("#syncLogoutBtn");
    if(f) f.style.display=ok?"none":"block";
    if(b) b.style.display=ok?"block":"none";
  }
  function localData(){
    try { const d=JSON.parse(localStorage.getItem("nuestraCasaDemo")||"null"); if(d&&d.events&&d.tasks&&d.shopping&&d.meals)return d; } catch(e){}
    return null;
  }
  async function writeNow(){
    if(!ready || !client || !householdId || !user)return;
    if(busy){queued=true;return}
    busy=true;
    try {
      do {
        queued=false;
        const data=localData();
        if(!data)throw new Error("No encuentro los datos guardados en este teléfono.");
        const {error}=await client.from("family_app_state").upsert({
          household_id:householdId, data, updated_by:user.id, updated_at:new Date().toISOString()
        },{onConflict:"household_id"});
        if(error)throw error;
      } while(queued);
      status("Conectado y sincronizado. Los cambios se guardan para toda la familia.",true);
    } catch(e) {
      status("Sesión abierta, pero no se pudo guardar en la nube: "+(e.message||"error de conexión")+". Los datos de este teléfono siguen guardados.");
    } finally { busy=false; }
  }
  function scheduleSave(){
    if(!ready)return;
    clearTimeout(timer);
    timer=setTimeout(writeNow,500);
  }
  async function connectUser(authUser){
    ready=false; user=authUser; householdId=null; showConnected(true);
    status("Sesión iniciada. Buscando la casa familiar…");
    try {
      const {data:members,error:mErr}=await client.from("household_member").select("household_id").eq("user_id",authUser.id).limit(1);
      if(mErr)throw mErr;
      if(!members||!members.length){
        status("La cuenta ha iniciado sesión, pero aún no está asociada a una casa. En GitHub abre supabase-sync-setup.sql, sustituye REPLACE_WITH_YOUR_EMAIL por tu correo y ejecuta el script completo en SQL Editor.");
        showConnected(false);return;
      }
      householdId=members[0].household_id;
      status("Casa encontrada. Leyendo los datos compartidos…");
      const {data:row,error:rErr}=await client.from("family_app_state").select("data").eq("household_id",householdId).maybeSingle();
      if(rErr)throw rErr;
      if(row && row.data && Array.isArray(row.data.events)&&Array.isArray(row.data.tasks)&&Array.isArray(row.data.shopping)&&Array.isArray(row.data.meals)){
        ready=false;
        window.dispatchEvent(new CustomEvent("nuestra-casa-cloud-load",{detail:row.data}));
        ready=true;
        status("Sincronizado. Este móvil ya utiliza los datos compartidos de Nuestra Casa.",true);
        showConnected(true);
      }else{
        ready=true;
        status("Primera sincronización: guardando los datos que ya tienes en este teléfono…");
        await writeNow();
        showConnected(true);
      }
    } catch(e){
      ready=false; householdId=null;
      status("No se ha podido completar la conexión: "+(e.message||"error desconocido")+". Tus datos locales se conservan.");
      showConnected(false);
    }
  }
  async function init(){
    if(!window.supabase||!window.supabase.createClient){
      status("No se ha podido cargar la conexión. Comprueba internet y recarga Nuestra Casa.");return;
    }
    client=window.supabase.createClient(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY,{
      auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}
    });
    const form=$("#syncLoginForm");
    if(form)form.addEventListener("submit",async e=>{
      e.preventDefault();
      const email=$("#syncEmail").value.trim(), password=$("#syncPassword").value;
      const btn=$("#syncLoginBtn"); btn.disabled=true; btn.textContent="Conectando…";
      status("Iniciando sesión en la cuenta familiar…");
      try{
        const {data,error}=await client.auth.signInWithPassword({email,password});
        if(error)throw error;
        $("#syncPassword").value="";
        await connectUser(data.user);
      }catch(err){
        status("No se ha podido iniciar sesión: "+(err.message||"comprueba el correo y la contraseña")+". Tus datos locales siguen intactos.");
        showConnected(false);
      }finally{btn.disabled=false;btn.textContent="Conectar y sincronizar";}
    });
    const out=$("#syncLogoutBtn");
    if(out)out.addEventListener("click",async()=>{
      ready=false;householdId=null;user=null;
      const {error}=await client.auth.signOut();
      showConnected(false);
      status(error?"Sesión cerrada localmente; comprueba la conexión.":"Sesión cerrada en este teléfono. Los datos locales se conservan.");
    });
    const imp=$("#importDataBtn");
    if(imp)imp.addEventListener("click",()=>{
      const file=$("#importDataFile")&&$("#importDataFile").files[0];
      if(!file){alert("Selecciona el archivo nuestra-casa-copia.json primero.");return;}
      const reader=new FileReader();
      reader.onload=()=>{
        try{
          const parsed=JSON.parse(reader.result), d=parsed.data||parsed;
          if(!d||!Array.isArray(d.events)||!Array.isArray(d.tasks)||!Array.isArray(d.shopping)||!Array.isArray(d.meals))throw new Error("El archivo no tiene el formato de copia de Nuestra Casa.");
          if(!confirm("La copia reemplazará los datos de este teléfono. Si está conectado, los actualizará también en la nube. ¿Continuar?"))return;
          window.dispatchEvent(new CustomEvent("nuestra-casa-cloud-load",{detail:d}));
          status(ready?"Copia restaurada. Guardando la nueva versión compartida…":"Copia restaurada en este teléfono. Conéctate para compartirla con la familia.",true);
          if(ready)scheduleSave();
        }catch(err){alert(err.message||"No se ha podido leer el archivo.");}
      };
      reader.onerror=()=>alert("No se ha podido leer el archivo.");
      reader.readAsText(file);
    });
    client.auth.onAuthStateChange((event,session)=>{
      if(event==="SIGNED_OUT"){ready=false;householdId=null;user=null;showConnected(false);}
    });
    const {data,error}=await client.auth.getSession();
    if(error){status("No se ha podido recuperar la sesión: "+error.message);return;}
    if(data.session&&data.session.user)await connectUser(data.session.user);
    else{showConnected(false);status("Sin conectar. Inicia sesión una vez en este teléfono para compartir los datos con la familia.");}
  }
  window.addEventListener("nuestra-casa-local-save",scheduleSave);
  window.addEventListener("DOMContentLoaded",init);
})();
