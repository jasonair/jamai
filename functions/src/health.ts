import { onRequest } from 'firebase-functions/v2/https';


export const health = onRequest({ invoker: 'private' }, (req, res) => {
  res.status(200).send('ok');
});
