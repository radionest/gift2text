export function copyToClipboard(text, onSuccess, onFailure) {
  navigator.clipboard.writeText(text).then(
    () => onSuccess(),
    () => onFailure()
  );
}
