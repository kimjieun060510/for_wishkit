import type { AppSyncResolverHandler } from 'aws-lambda';
import {
  isValidHttpUrl,
  isValidImageInput,
  toExtractedProduct,
  toIdentifiedTag,
  type EngineExtractResponse,
  type EngineIdentifyResponse,
  type ExtractedProduct,
  type IdentifiedTag,
} from './logic';

// backend.ts 가 넣어 주는 엔진 서버 내부 주소(예: http://<내부 ALB DNS>). VPC 안에서만
// 닿는 주소라 이 값 자체는 비밀이 아니다 — 실제 접근 통제는 보안그룹이 한다.
const ENGINE_BASE_URL = process.env.ENGINE_BASE_URL ?? '';

// 엔진 서버 자체 타임아웃(/extract 45초)보다 여유를 주되, 이 함수의 timeoutSeconds(60,
// resource.ts)보다는 짧게 잡아서 Lambda가 강제 종료되기 전에 정상적인 에러 메시지를 돌려준다.
const FETCH_TIMEOUT_MS = 55_000;

// ⚠️ AppSync는 Lambda 리졸버를 30초까지만 기다린다(늘릴 수 없는 한도). /identify-tag는
// 엔진 쪽 25초(IDENTIFY_TIMEOUT_S) + 여유로 27초에 끊어서, 앱이 AppSync 타임아웃 대신
// 알아볼 수 있는 오류를 받게 한다. (기존 /extract의 55초도 같은 한도에 걸린다 — 앱에
// 연결하기 전에 따로 정리 필요)
const IDENTIFY_FETCH_TIMEOUT_MS = 27_000;

// 이 함수 하나가 GraphQL 필드 두 개를 처리한다(VPC 연결 설정을 한 번만 하려고).
type Args =
  | { url: string }
  | { imageBase64: string; mimeType: string };

export const handler: AppSyncResolverHandler<Args, ExtractedProduct | IdentifiedTag> = async (event) => {
  if (!ENGINE_BASE_URL) {
    throw new Error('엔진 서버 주소가 설정되지 않았습니다(ENGINE_BASE_URL 환경변수 확인).');
  }
  switch (event.info.fieldName) {
    case 'identifyProductTag': {
      const { imageBase64, mimeType } = event.arguments as { imageBase64: string; mimeType: string };
      if (!isValidImageInput(imageBase64, mimeType)) {
        throw new Error('사진 형식이 올바르지 않거나 너무 큽니다.');
      }
      const body = await postToEngine<EngineIdentifyResponse>(
        '/identify-tag',
        { image_base64: imageBase64, mime_type: mimeType },
        IDENTIFY_FETCH_TIMEOUT_MS,
      );
      return toIdentifiedTag(body);
    }
    case 'extractProduct': {
      const { url } = event.arguments as { url: string };
      if (!isValidHttpUrl(url)) {
        throw new Error('유효하지 않은 URL입니다.');
      }
      const body = await postToEngine<EngineExtractResponse>('/extract', { url }, FETCH_TIMEOUT_MS);
      return toExtractedProduct(body);
    }
    default:
      // 원래는 모르는 필드도 /extract로 흘러갔다 — 스키마에 필드를 추가하고 여기를 빠뜨리면
      // 엉뚱한 호출 대신 바로 알아챌 수 있게 막는다.
      throw new Error(`Unknown field: ${event.info.fieldName}`);
  }
};

async function postToEngine<T>(path: string, payload: unknown, timeoutMs: number): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const resp = await fetch(`${ENGINE_BASE_URL}${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
    if (!resp.ok) {
      const detail = await resp.text().catch(() => '');
      throw new Error(`엔진 서버 오류(${resp.status}): ${detail}`);
    }
    return (await resp.json()) as T;
  } catch (exc) {
    if (exc instanceof Error && exc.name === 'AbortError') {
      throw new Error('엔진 서버 응답이 너무 오래 걸려 취소되었습니다.');
    }
    throw exc;
  } finally {
    clearTimeout(timeout);
  }
}
