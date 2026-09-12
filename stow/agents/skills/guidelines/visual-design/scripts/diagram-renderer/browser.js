import { exportToBlob, restoreElements } from '@excalidraw/excalidraw';

window.renderDiagram = async (scene, scale) => {
  const blob = await exportToBlob({
    elements: restoreElements(scene.elements, null),
    files: scene.files || {},
    appState: {
      ...scene.appState,
      exportBackground: true,
      viewBackgroundColor: scene.appState?.viewBackgroundColor || '#ffffff',
      exportWithDarkMode: false,
    },
    exportPadding: 24,
    getDimensions: (width, height) => ({ width: width * scale, height: height * scale, scale }),
    mimeType: 'image/png',
  });
  if (!blob) throw new Error('Excalidraw produced no image');
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result.split(',')[1]);
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
};
