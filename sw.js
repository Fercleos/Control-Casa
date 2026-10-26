// Versión de caché/despliegue: nuestra-casa-v2026-10-26-1.
// Este trabajador de recuperación elimina las cachés antiguas y se desregistra para cargar siempre los archivos actuales.
self.addEventListener("install",e=>{self.skipWaiting();});
self.addEventListener("activate",e=>e.waitUntil(
 caches.keys().then(keys=>Promise.all(keys.map(k=>caches.delete(k))))
 .then(()=>self.registration.unregister())
 .then(()=>self.clients.matchAll({type:"window",includeUncontrolled:true}))
 .then(clients=>Promise.all(clients.map(client=>client.navigate(client.url))))
));
self.addEventListener("fetch",e=>{});
